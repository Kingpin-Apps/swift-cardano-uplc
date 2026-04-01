import Foundation
import SwiftCardanoCore
import SwiftCardanoChain

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

// MARK: — Builtin cost model (simplified — linear model)

/// Cost for a single builtin invocation, expressed as a linear function of input sizes.
/// `cost = intercept + slope * size`
public struct LinearCost: Sendable {
    public var intercept: Int64
    public var slope: Int64
    public init(intercept: Int64, slope: Int64 = 0) {
        self.intercept = intercept
        self.slope = slope
    }
    public func evaluate(size: Int64) -> ExBudget {
        ExBudget(cpu: intercept + slope * size, mem: 1)
    }
}

/// Per-builtin cost entry (CPU + memory, each a linear function of argument size).
public struct BuiltinCost: Sendable {
    public var cpu: LinearCost
    public var mem: LinearCost
    public init(cpu: LinearCost, mem: LinearCost) {
        self.cpu = cpu
        self.mem = mem
    }
    /// Flat cost regardless of arguments.
    public static func flat(cpu: Int64, mem: Int64) -> BuiltinCost {
        BuiltinCost(cpu: LinearCost(intercept: cpu), mem: LinearCost(intercept: mem))
    }
}

// MARK: — CostModel

/// The complete cost model for CEK machine evaluation.
public struct CostModel: Sendable {
    public let machineStepCosts: MachineStepCosts
    public let builtinCosts: [DefaultFunction: BuiltinCost]

    public init(machineStepCosts: MachineStepCosts, builtinCosts: [DefaultFunction: BuiltinCost]) {
        self.machineStepCosts = machineStepCosts
        self.builtinCosts = builtinCosts
    }

    /// Approximate V2 PlutusV2 default cost model.
    /// For production use, load from a live chain context instead.
    public static func defaultV2() -> CostModel {
        let step = ExBudget(cpu: 16_000, mem: 100)
        let stepCosts = MachineStepCosts(
            startup:  ExBudget(cpu: 100, mem: 100),
            variable: step,
            constant: step,
            lambda:   step,
            delay:    step,
            force:    step,
            apply:    step,
            constr:   ExBudget(cpu: 30_000_000_000, mem: 100), // placeholder pre-Conway
            kase:     ExBudget(cpu: 30_000_000_000, mem: 100),
            builtin:  step
        )
        // Use a flat cost for all builtins as a placeholder.
        // Production usage should load from protocol parameters.
        var builtinCosts = [DefaultFunction: BuiltinCost]()
        for fn in DefaultFunction.allCases {
            builtinCosts[fn] = BuiltinCost.flat(cpu: 1_000_000, mem: 1_000)
        }
        return CostModel(machineStepCosts: stepCosts, builtinCosts: builtinCosts)
    }

    /// Load cost model from a static `ProtocolParameters` value.
    public static func fromProtocolParams(_ params: ProtocolParameters, version: PlutusVersion = .v2) throws -> CostModel {
        // The flat cost array is alphabetically ordered by parameter name in Cardano protocol params.
        // For now we use the default model — a full implementation maps the [Int] array
        // to named fields using the Plutus cost model specification.
        return .defaultV2()
    }

    /// Load cost model from a live chain context.
    public static func fromChainContext(_ context: any ChainContext) async throws -> CostModel {
        let params = try await context.protocolParameters()
        return try fromProtocolParams(params)
    }
}

/// Plutus script language version.
public enum PlutusVersion: Sendable {
    case v1, v2, v3
}
