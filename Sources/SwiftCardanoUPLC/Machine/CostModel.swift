import Foundation
import SwiftCardanoCore

// MARK: — ExBudget

/// Execution budget in CPU steps and memory units.
public struct ExBudget: Sendable, Equatable {
    public var cpu: Int64
    public var mem: Int64

    public init(cpu: Int64, mem: Int64) {
        self.cpu = cpu
        self.mem = mem
    }

    /// Default restricted budget (matches Cardano mainnet default).
    public static let restricted = ExBudget(cpu: 10_000_000_000, mem: 14_000_000)
    /// Unlimited budget (for testing / offline evaluation).
    public static let unlimited  = ExBudget(cpu: .max, mem: .max)

    /// Deduct `cpu` and `mem` from this budget.
    /// Throws `MachineError.outOfExBudget` if either goes negative.
    public mutating func spend(cpu: Int64, mem: Int64) throws {
        self.cpu -= cpu
        self.mem -= mem
        if self.cpu < 0 || self.mem < 0 {
            throw MachineError.outOfExBudget(self)
        }
    }
}

// MARK: — Step costs

/// Per-step cost for each CEK machine state transition.
public struct MachineStepCosts: Sendable {
    public var startup: ExBudget
    public var variable: ExBudget
    public var constant: ExBudget
    public var lambda: ExBudget
    public var delay: ExBudget
    public var force: ExBudget
    public var apply: ExBudget
    public var constr: ExBudget
    public var kase: ExBudget   // `case` is a Swift keyword
    public var builtin: ExBudget

    public init(startup: ExBudget, variable: ExBudget, constant: ExBudget,
                lambda: ExBudget, delay: ExBudget, force: ExBudget,
                apply: ExBudget, constr: ExBudget, kase: ExBudget, builtin: ExBudget) {
        self.startup  = startup
        self.variable = variable
        self.constant = constant
        self.lambda   = lambda
        self.delay    = delay
        self.force    = force
        self.apply    = apply
        self.constr   = constr
        self.kase     = kase
        self.builtin  = builtin
    }
}

// MARK: — CostModel

/// The complete cost model for CEK machine evaluation.
public struct CostModel: Sendable {
    public let machineStepCosts: MachineStepCosts
    public let builtinCosts: [DefaultFunction: BuiltinCostingFunction]

    /// Whether these costs are placeholders rather than the chain's real
    /// cost model. Budgets from an approximate model are meaningless, so
    /// callers must not use budget exhaustion to decide whether a script
    /// passed.
    public let isApproximate: Bool

    public init(
        machineStepCosts: MachineStepCosts,
        builtinCosts: [DefaultFunction: BuiltinCostingFunction],
        isApproximate: Bool = false
    ) {
        self.machineStepCosts = machineStepCosts
        self.builtinCosts = builtinCosts
        self.isApproximate = isApproximate
    }

    /// The budget a builtin consumes for the given arguments, or `nil` when
    /// this cost model does not price it.
    ///
    /// An unpriced builtin is one the chain's cost model has no parameters
    /// for, which means the language version predates it and a script cannot
    /// legitimately call it. Costing it at zero would let such a script run
    /// for free, so callers must treat `nil` as an error.
    public func budget(for function: DefaultFunction, arguments: [Value]) -> ExBudget? {
        guard let costing = builtinCosts[function] else { return nil }
        return costing.budget(sizes: ExMemory.sizes(for: function, arguments: arguments))
    }

    /// A placeholder model, for evaluating a script when no protocol
    /// parameters are available. **Not** the chain's cost model — see
    /// ``isApproximate``.
    public static func placeholder() -> CostModel {
        let step = ExBudget(cpu: 16_000, mem: 100)
        let stepCosts = MachineStepCosts(
            startup:  ExBudget(cpu: 100, mem: 100),
            variable: step, constant: step, lambda: step, delay: step,
            force: step, apply: step, constr: step, kase: step, builtin: step
        )
        var builtinCosts = [DefaultFunction: BuiltinCostingFunction]()
        for fn in DefaultFunction.allCases {
            builtinCosts[fn] = BuiltinCostingFunction(
                cpu: .constant(1_000_000), memory: .constant(1_000)
            )
        }
        return CostModel(
            machineStepCosts: stepCosts, builtinCosts: builtinCosts, isApproximate: true
        )
    }

    @available(*, deprecated, renamed: "placeholder")
    public static func defaultV2() -> CostModel { placeholder() }

    /// Build the cost model the chain is currently using.
    ///
    /// Protocol parameters carry each language's cost model as a bare array of
    /// integers; the ledger tags them by position using a fixed parameter
    /// order (see ``CostModelParameterNames``). The *shapes* of the costing
    /// functions come from the Plutus release and are fixed per language
    /// version; only the coefficients come from the chain.
    ///
    /// - Throws: ``CostModelError`` when the chain supplies no cost model for
    ///   the requested version, or one too short to name every parameter the
    ///   costing functions need.
    public static func fromProtocolParams(
        _ params: ProtocolParameters,
        version: PlutusVersion = .v2
    ) throws -> CostModel {
        let protocolMajorVersion = Int(params.protocolVersion.major)
        let languageId: Int
        let names: [String]
        switch version {
        case .v1: languageId = 1; names = CostModelParameterNames.plutusv1
        case .v2: languageId = 2; names = CostModelParameterNames.plutusv2
        case .v3: languageId = 3; names = CostModelParameterNames.plutusv3
        }

        guard let values = params.costModels.getVersion(languageId), !values.isEmpty else {
            throw CostModelError.missingCostModel(version)
        }

        // A shorter array is an older chain that predates the newest
        // parameters; a longer one is a newer chain whose extra parameters
        // this build has no names for. Either way, pair up what we can.
        var table = [String: Int64](minimumCapacity: values.count)
        for (name, value) in zip(names, values) { table[name] = value }

        return try fromParameters(table, version: version, supplied: values.count, protocolMajorVersion: protocolMajorVersion)
    }

    /// Build a cost model from cost-model parameters keyed by name.
    ///
    /// This is the form the Plutus cost-model data files use; protocol
    /// parameters are the same values positionally.
    /// - Parameter protocolMajorVersion: decides which builtin semantics variant
    ///   prices the language — see ``builtinCosts(version:protocolMajorVersion:_:)``.
    ///   Defaults to Chang, the first version Conway transactions are validated
    ///   under.
    public static func fromParameters(
        _ table: [String: Int64],
        version: PlutusVersion,
        supplied: Int? = nil,
        protocolMajorVersion: Int = 9
    ) throws -> CostModel {
        var missing: [String] = []
        let lookup: (String) -> Int64 = { name in
            guard let value = table[name] else {
                missing.append(name)
                return 0
            }
            return value
        }

        let stepCosts = MachineStepCosts(
            startup:  ExBudget(cpu: lookup("cekStartupCost-exBudgetCPU"),
                               mem: lookup("cekStartupCost-exBudgetMemory")),
            variable: ExBudget(cpu: lookup("cekVarCost-exBudgetCPU"),
                               mem: lookup("cekVarCost-exBudgetMemory")),
            constant: ExBudget(cpu: lookup("cekConstCost-exBudgetCPU"),
                               mem: lookup("cekConstCost-exBudgetMemory")),
            lambda:   ExBudget(cpu: lookup("cekLamCost-exBudgetCPU"),
                               mem: lookup("cekLamCost-exBudgetMemory")),
            delay:    ExBudget(cpu: lookup("cekDelayCost-exBudgetCPU"),
                               mem: lookup("cekDelayCost-exBudgetMemory")),
            force:    ExBudget(cpu: lookup("cekForceCost-exBudgetCPU"),
                               mem: lookup("cekForceCost-exBudgetMemory")),
            apply:    ExBudget(cpu: lookup("cekApplyCost-exBudgetCPU"),
                               mem: lookup("cekApplyCost-exBudgetMemory")),
            // Constr and case arrived with Plutus Core 1.1.0, so a PlutusV1 or
            // V2 cost model does not price them. Those languages cannot
            // contain the terms either, so the cost is never charged.
            constr:   version == .v3
                ? ExBudget(cpu: lookup("cekConstrCost-exBudgetCPU"),
                           mem: lookup("cekConstrCost-exBudgetMemory"))
                : ExBudget(cpu: 0, mem: 0),
            kase:     version == .v3
                ? ExBudget(cpu: lookup("cekCaseCost-exBudgetCPU"),
                           mem: lookup("cekCaseCost-exBudgetMemory"))
                : ExBudget(cpu: 0, mem: 0),
            builtin:  ExBudget(cpu: lookup("cekBuiltinCost-exBudgetCPU"),
                               mem: lookup("cekBuiltinCost-exBudgetMemory"))
        )

        // The machine step costs are not optional: without them nothing can
        // be costed at all.
        guard missing.isEmpty else {
            throw CostModelError.incompleteCostModel(
                version: version, supplied: supplied ?? table.count, missing: missing.sorted()
            )
        }

        missing.removeAll()
        var builtinCosts = builtinCosts(
            version: version, protocolMajorVersion: protocolMajorVersion, lookup
        )

        // A cost model from an older chain does not name the parameters of
        // builtins that did not exist yet. Those builtins are simply not
        // available in that protocol version, so drop them rather than
        // rejecting the whole model — a script cannot call them, and if one
        // somehow does the evaluator reports it instead of silently costing
        // it at zero.
        if !missing.isEmpty {
            let unpriced = Set(missing.map { String($0.prefix(while: { $0 != "-" })) })
            builtinCosts = builtinCosts.filter { !unpriced.contains("\($0.key)") }
        }

        return CostModel(
            machineStepCosts: stepCosts, builtinCosts: builtinCosts, isApproximate: false
        )
    }
}

/// Raised when a usable cost model cannot be built from protocol parameters.
public enum CostModelError: Error, Sendable, Equatable {
    /// The protocol parameters carry no cost model for this language version.
    case missingCostModel(PlutusVersion)
    /// The supplied cost model does not name every parameter the costing
    /// functions need — an older chain, or a newer one this build predates.
    case incompleteCostModel(version: PlutusVersion, supplied: Int, missing: [String])
}

/// Plutus script language version.
public enum PlutusVersion: Sendable {
    case v1, v2, v3
}
