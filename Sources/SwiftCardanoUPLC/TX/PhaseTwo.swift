import Foundation
import SwiftCardanoCore

/// Result of evaluating all scripts in a transaction.
public struct PhaseTwoResult: Sendable {
    /// Per-redeemer evaluation outcomes.
    public let redeemers: [RedeemerResult]
    /// True if all scripts passed.
    public var success: Bool { redeemers.allSatisfy(\.passed) }
}

/// Outcome for a single redeemer's script evaluation.
public struct RedeemerResult: Sendable {
    public let index: Int
    public let passed: Bool
    public let remainingBudget: ExBudget
    public let logs: [String]
    public let error: MachineError?
    /// Whether `remainingBudget` reflects a real cost model.
    ///
    /// False when evaluation used the placeholder cost model, in which case
    /// the budget is not meaningful and must not be reported as execution
    /// units or compared against the transaction's declared units.
    public let budgetMeasured: Bool

    public init(
        index: Int,
        passed: Bool,
        remainingBudget: ExBudget,
        logs: [String],
        error: MachineError?,
        budgetMeasured: Bool = false
    ) {
        self.index = index
        self.passed = passed
        self.remainingBudget = remainingBudget
        self.logs = logs
        self.error = error
        self.budgetMeasured = budgetMeasured
    }
}

/// Evaluates all Plutus scripts in a transaction (Phase 2 validation).
///
/// Scripts run in parallel via Swift structured concurrency.
/// Each redeemer gets its own independent `CEKMachine` instance.
public struct PhaseTwo: @unchecked Sendable {
    private let costModels: [PlutusVersion: CostModel]

    /// Primary initializer — caller supplies a cost model used for every
    /// language version.
    public init(costModel: CostModel) {
        self.costModels = [.v1: costModel, .v2: costModel, .v3: costModel]
    }

    /// Derive cost models from protocol parameters.
    ///
    /// A cost model is per language version, and a transaction can execute
    /// scripts of more than one. Each script is costed with the model for its
    /// own version — costing a PlutusV3 script with the V2 model prices four
    /// builtins by the wrong formula and misreports every budget.
    ///
    /// - Parameter version: when given, only that version's model is built and
    ///   it is used for every script. Prefer omitting it.
    public init(protocolParameters: ProtocolParameters, version: PlutusVersion? = nil) throws {
        if let version {
            let model = try CostModel.fromProtocolParams(protocolParameters, version: version)
            self.costModels = [.v1: model, .v2: model, .v3: model]
            return
        }
        var models: [PlutusVersion: CostModel] = [:]
        var lastError: Error?
        for candidate in [PlutusVersion.v1, .v2, .v3] {
            do {
                models[candidate] = try CostModel.fromProtocolParams(
                    protocolParameters, version: candidate
                )
            } catch {
                lastError = error
            }
        }
        guard !models.isEmpty else {
            throw lastError ?? CostModelError.missingCostModel(.v3)
        }
        self.costModels = models
    }

    /// Evaluate all Plutus scripts in a transaction.
    ///
    /// - Parameters:
    ///   - transaction: The transaction whose scripts to evaluate.
    ///   - resolvedInputs: All transaction inputs resolved to UTxOs (including reference inputs).
    /// - Returns: `PhaseTwoResult` with per-redeemer outcomes.
    public func evaluate(
        transaction: Transaction,
        resolvedInputs: [UTxO]
    ) async throws -> PhaseTwoResult {
        let costModels = self.costModels
        let redeemers: [Redeemer]
        if let rs = transaction.transactionWitnessSet.redeemers {
            switch rs {
            case .list(let list):
                redeemers = list.compactMap { $0 as? Redeemer }
            case .map(let map):
                // The tag and index live in the RedeemerKey — dropping them
                // leaves findScript with nothing to look the script up by.
                redeemers = map.dictionary.map { key, value in
                    Redeemer(
                        tag: key.tag,
                        index: key.index,
                        data: value.data,
                        exUnits: value.exUnits
                    )
                }
            }
        } else {
            redeemers = []
        }

        // Check upfront if any spending inputs are missing (e.g., already spent on-chain).
        let sortedInputs = transaction.transactionBody.inputs.asArray.sorted {
            if $0.transactionId.payload != $1.transactionId.payload {
                return $0.transactionId.payload.lexicographicallyPrecedes($1.transactionId.payload)
            }
            return $0.index < $1.index
        }

        var unresolvableIndices = Set<Int>()
        for (arrayIndex, redeemer) in redeemers.enumerated() where redeemer.tag == .spend {
            guard redeemer.index < sortedInputs.count else { continue }
            let spentInput = sortedInputs[redeemer.index]
            let isResolved = resolvedInputs.contains {
                $0.input.transactionId.payload == spentInput.transactionId.payload
                && $0.input.index == spentInput.index
            }
            if !isResolved {
                unresolvableIndices.insert(arrayIndex)
            }
        }

        let results: [RedeemerResult] = try await withThrowingTaskGroup(of: RedeemerResult.self) { group in
            for (index, redeemer) in redeemers.enumerated() {
                if unresolvableIndices.contains(index) {
                    // Skip evaluation; will add error result below
                    continue
                }
                group.addTask {
                    await evaluateSingleScript(
                        redeemer: redeemer,
                        index: index,
                        transaction: transaction,
                        resolvedInputs: resolvedInputs,
                        costModels: costModels
                    )
                }
            }
            var collected = [RedeemerResult]()
            for try await result in group {
                collected.append(result)
            }

            // Add error results for unresolvable spending redeemers
            for (arrayIndex, redeemer) in redeemers.enumerated() where unresolvableIndices.contains(arrayIndex) {
                var inputRef = "?"
                if redeemer.index < sortedInputs.count {
                    inputRef = sortedInputs[redeemer.index].description
                }
                let err = MachineError.typeError("Unresolved spent input for spend redeemer[\(arrayIndex)]: could not find UTxO for input \(inputRef)")
                collected.append(RedeemerResult(
                    index: arrayIndex,
                    passed: false,
                    remainingBudget: .restricted,
                    logs: [],
                    error: err
                ))
            }

            return collected.sorted { $0.index < $1.index }
        }

        return PhaseTwoResult(redeemers: results)
    }
}

// MARK: — Single-script evaluation

private func evaluateSingleScript(
    redeemer: Redeemer,
    index: Int,
    transaction: Transaction,
    resolvedInputs: [UTxO],
    costModels: [PlutusVersion: CostModel]
) async -> RedeemerResult {
    do {
        let (scriptData, version) = try findScript(
            for: redeemer, in: transaction, resolvedInputs: resolvedInputs
        )
        let flatBytes = try extractFlatBytes(from: scriptData)
        let program = try FlatDecoder().decode(flatBytes)
        let scriptContext = try buildScriptContext(
            for: redeemer, transaction: transaction,
            resolvedInputs: resolvedInputs, version: version
        )
        let applied = try applyArguments(
            program: program, redeemer: redeemer, scriptContext: scriptContext,
            transaction: transaction, resolvedInputs: resolvedInputs, version: version
        )
        // An approximate cost model cannot decide budget exhaustion — it
        // reports correct scripts as out of budget. Evaluate unmetered so the
        // outcome reflects the script's logic, and say so via
        // `budgetMeasured`.
        // Cost the script with the model for its own language version.
        guard let costModel = costModels[version] else {
            throw MachineError.typeError(
                "no cost model available for \(version); the chain's protocol parameters "
                + "carry none for that Plutus version."
            )
        }
        let budget: ExBudget = costModel.isApproximate ? .unlimited : .restricted
        var machine = CEKMachine(budget: budget, costModel: costModel)
        let result = try machine.run(applied)
        return RedeemerResult(index: index, passed: true,
                              remainingBudget: result.remainingBudget,
                              logs: result.logs, error: nil,
                              budgetMeasured: !costModel.isApproximate)
    } catch let err as MachineError {
        return RedeemerResult(index: index, passed: false,
                              remainingBudget: .restricted,
                              logs: [], error: err)
    } catch {
        // Anything thrown outside the machine — flat decoding, script lookup,
        // script-context construction — is not an `error` term being
        // evaluated. Reporting it as `.evaluationFailure` hides the real
        // cause behind "the script said no", which is the one thing it does
        // not mean.
        return RedeemerResult(index: index, passed: false,
                              remainingBudget: .restricted,
                              logs: [],
                              error: .typeError("script could not be prepared for evaluation: \(error)"))
    }
}

// MARK: — Script lookup

/// Locate the Plutus script for a given redeemer by traversing the transaction
/// witness set and reference scripts on resolved UTxOs.
/// - Returns: A tuple of the raw script `Data` (CBOR-wrapped flat bytes) and the `PlutusVersion`.
private func findScript(
    for redeemer: Redeemer,
    in transaction: Transaction,
    resolvedInputs: [UTxO]
) throws -> (Data, PlutusVersion) {
    let witnesses = transaction.transactionWitnessSet
    let body = transaction.transactionBody

    // Collect all available scripts with their hashes and versions.
    var scriptMap = [Data: (Data, PlutusVersion)]()

    // From witness set
    if let v1Scripts = witnesses.plutusV1Script {
        for script in v1Scripts.asList {
            let hash = try plutusScriptHash(script: .plutusV1Script(script))
            scriptMap[hash.payload] = (script.data, .v1)
        }
    }
    if let v2Scripts = witnesses.plutusV2Script {
        for script in v2Scripts.asList {
            let hash = try plutusScriptHash(script: .plutusV2Script(script))
            scriptMap[hash.payload] = (script.data, .v2)
        }
    }
    if let v3Scripts = witnesses.plutusV3Script {
        for script in v3Scripts.asList {
            let hash = try plutusScriptHash(script: .plutusV3Script(script))
            scriptMap[hash.payload] = (script.data, .v3)
        }
    }

    // From reference scripts on resolved inputs
    for utxo in resolvedInputs {
        if let scriptType = utxo.output.script {
            switch scriptType {
            case .plutusV1Script(let s):
                let hash = try plutusScriptHash(script: .plutusV1Script(s))
                scriptMap[hash.payload] = (s.data, .v1)
            case .plutusV2Script(let s):
                let hash = try plutusScriptHash(script: .plutusV2Script(s))
                scriptMap[hash.payload] = (s.data, .v2)
            case .plutusV3Script(let s):
                let hash = try plutusScriptHash(script: .plutusV3Script(s))
                scriptMap[hash.payload] = (s.data, .v3)
            case .nativeScript:
                break // Not a Plutus script
            }
        }
    }

    // Determine which script hash this redeemer refers to.
    let targetHash: Data
    switch redeemer.tag {
    case .spend:
        // Redeemer index refers to the sorted position in the tx inputs
        let sortedInputs = body.inputs.asArray.sorted {
            if $0.transactionId.payload != $1.transactionId.payload {
                return $0.transactionId.payload.lexicographicallyPrecedes($1.transactionId.payload)
            }
            return $0.index < $1.index
        }
        guard redeemer.index < sortedInputs.count else {
            throw MachineError.typeError("findScript: spend redeemer index \(redeemer.index) out of range")
        }
        let spentInput = sortedInputs[redeemer.index]
        // Find the UTxO for this input and extract the script hash from its address
        guard let utxo = resolvedInputs.first(where: {
            $0.input.transactionId.payload == spentInput.transactionId.payload
            && $0.input.index == spentInput.index
        }) else {
            throw MachineError.typeError("findScript: could not resolve input for spend redeemer")
        }
        guard case .scriptHash(let sh) = utxo.output.address.paymentPart else {
            throw MachineError.typeError("findScript: spent input address is not a script address")
        }
        targetHash = sh.payload

    case .mint:
        // Redeemer index refers to the sorted position of policy IDs in the mint field
        guard let mint = body.mint else {
            throw MachineError.typeError("findScript: mint redeemer but no mint field in tx body")
        }
        let sortedPolicies = mint.data.keys.sorted {
            $0.payload.lexicographicallyPrecedes($1.payload)
        }
        guard redeemer.index < sortedPolicies.count else {
            throw MachineError.typeError("findScript: mint redeemer index \(redeemer.index) out of range")
        }
        targetHash = sortedPolicies[redeemer.index].payload

    case .reward:
        // The index counts through the withdrawals in the ledger's reward
        // account order, which puts script credentials before key ones.
        let entries = orderedWithdrawalCredentials(body.withdrawals)
        guard redeemer.index < entries.count else {
            throw MachineError.typeError(
                "findScript: reward redeemer index \(redeemer.index) out of range")
        }
        let credential = entries[redeemer.index]
        guard credential.isScript else {
            throw MachineError.typeError(
                "findScript: reward redeemer points at a key-credential withdrawal, "
                + "which needs a signature rather than a script")
        }
        targetHash = credential.hash

    default:
        throw MachineError.typeError("findScript: redeemer tag \(String(describing: redeemer.tag)) not yet supported")
    }

    guard let found = scriptMap[targetHash] else {
        throw MachineError.typeError("findScript: no script found matching hash \(targetHash.map { String(format: "%02x", $0) }.joined())")
    }
    return found
}

// MARK: — CBOR unwrapping

/// Extract the flat-encoded script bytes from a CBOR-wrapped script envelope.
/// `PlutusV*Script.data` is a single CBOR bytestring wrapping the flat bytes.
private func extractFlatBytes(from scriptData: Data) throws -> Data {
    // The script data is CBOR-encoded: a single CBOR bytestring containing flat bytes.
    // Decode one CBOR layer to get the inner bytes.
    guard scriptData.count > 1 else { return scriptData }

    // CBOR major type 2 (byte string) check:
    // If the first byte's major type is 2 (0x40..0x5f), this is CBOR-wrapped.
    let firstByte = scriptData[scriptData.startIndex]
    let majorType = (firstByte & 0xE0) >> 5
    if majorType == 2 {
        // Decode the CBOR bytestring
        let primitive = try Primitive.fromCBOR(data: scriptData)
        if case .bytes(let innerBytes) = primitive {
            return innerBytes
        }
    }
    // If not CBOR-wrapped, return as-is (already flat bytes)
    return scriptData
}

// MARK: — Script context construction

private func buildScriptContext(
    for redeemer: Redeemer,
    transaction: Transaction,
    resolvedInputs: [UTxO],
    version: PlutusVersion
) throws -> PlutusData {
    let builder = ScriptContextBuilder()
    let body = transaction.transactionBody

    switch redeemer.tag {
    case .spend:
        let sortedInputs = body.inputs.asArray.sorted {
            if $0.transactionId.payload != $1.transactionId.payload {
                return $0.transactionId.payload.lexicographicallyPrecedes($1.transactionId.payload)
            }
            return $0.index < $1.index
        }
        guard redeemer.index < sortedInputs.count else {
            throw MachineError.typeError("buildScriptContext: spend index out of range")
        }
        let spentInput = sortedInputs[redeemer.index]
        if version == .v3 {
            // V3 carries the datum inside the context's ScriptInfo rather than
            // passing it as a separate argument.
            let datum = try? findDatum(
                for: redeemer, transaction: transaction, resolvedInputs: resolvedInputs
            )
            return try builder.spendingContextV3(
                transaction: transaction,
                spentInput: spentInput,
                resolvedInputs: resolvedInputs,
                redeemer: redeemer.data,
                datum: datum
            )
        }
        return try builder.spendingContext(
            transaction: transaction,
            spentInput: spentInput,
            resolvedInputs: resolvedInputs,
            version: version
        )

    case .mint:
        guard let mint = body.mint else {
            throw MachineError.typeError("buildScriptContext: mint redeemer but no mint field")
        }
        let sortedPolicies = mint.data.keys.sorted {
            $0.payload.lexicographicallyPrecedes($1.payload)
        }
        guard redeemer.index < sortedPolicies.count else {
            throw MachineError.typeError("buildScriptContext: mint index out of range")
        }
        let policyId = sortedPolicies[redeemer.index].payload
        if version == .v3 {
            return try builder.mintingContextV3(
                transaction: transaction,
                resolvedInputs: resolvedInputs,
                policyId: policyId,
                redeemer: redeemer.data
            )
        }
        return try builder.mintingContext(
            transaction: transaction,
            resolvedInputs: resolvedInputs,
            policyId: policyId,
            version: version
        )

    case .reward:
        let entries = orderedWithdrawalCredentials(body.withdrawals)
        guard redeemer.index < entries.count else {
            throw MachineError.typeError("buildScriptContext: reward index out of range")
        }
        let credential = entries[redeemer.index]
        if version == .v3 {
            return try builder.rewardingContextV3(
                transaction: transaction,
                resolvedInputs: resolvedInputs,
                stakeCredentialHash: credential.hash,
                isScript: credential.isScript,
                redeemer: redeemer.data
            )
        }
        return try builder.rewardingContext(
            transaction: transaction,
            resolvedInputs: resolvedInputs,
            stakeCredentialHash: credential.hash,
            isScript: credential.isScript,
            version: version
        )

    default:
        throw MachineError.typeError("buildScriptContext: redeemer tag \(String(describing: redeemer.tag)) not yet supported")
    }
}

// MARK: — Argument application

private func applyArguments(
    program: NamedDeBruijnProgram,
    redeemer: Redeemer,
    scriptContext: PlutusData,
    transaction: Transaction,
    resolvedInputs: [UTxO],
    version: PlutusVersion
) throws -> NamedDeBruijnProgram {
    var term = program.term

    // A V3 script takes exactly one argument: the ScriptContext. Both the
    // redeemer and (for spending scripts) the datum live inside it. Passing
    // them separately, as V1/V2 require, over-applies the script.
    if version == .v3 {
        let ctxTerm = Term<NamedDeBruijn>.constant(.data(scriptContext))
        return NamedDeBruijnProgram(
            version: program.version,
            term: .apply(function: term, argument: ctxTerm)
        )
    }

    // For V1/V2 spending scripts, prepend datum as the first argument
    if redeemer.tag == .spend {
        let datum = try findDatum(
            for: redeemer, transaction: transaction, resolvedInputs: resolvedInputs
        )
        let datumTerm = Term<NamedDeBruijn>.constant(.data(datum))
        term = .apply(function: term, argument: datumTerm)
    }

    // Apply redeemer
    let redeemerTerm = Term<NamedDeBruijn>.constant(.data(redeemer.data))
    term = .apply(function: term, argument: redeemerTerm)

    // Apply script context
    let ctxTerm = Term<NamedDeBruijn>.constant(.data(scriptContext))
    term = .apply(function: term, argument: ctxTerm)

    return NamedDeBruijnProgram(version: program.version, term: term)
}

// MARK: — Datum resolution

/// Find the datum for a spending redeemer by checking inline datums on the spent UTxO
/// or looking up the datum hash in the transaction witness set.
private func findDatum(
    for redeemer: Redeemer,
    transaction: Transaction,
    resolvedInputs: [UTxO]
) throws -> PlutusData {
    let body = transaction.transactionBody
    let sortedInputs = body.inputs.asArray.sorted {
        if $0.transactionId.payload != $1.transactionId.payload {
            return $0.transactionId.payload.lexicographicallyPrecedes($1.transactionId.payload)
        }
        return $0.index < $1.index
    }
    guard redeemer.index < sortedInputs.count else {
        throw MachineError.typeError("findDatum: spend index out of range")
    }
    let spentInput = sortedInputs[redeemer.index]
    guard let utxo = resolvedInputs.first(where: {
        $0.input.transactionId.payload == spentInput.transactionId.payload
        && $0.input.index == spentInput.index
    }) else {
        throw MachineError.typeError("findDatum: could not resolve spent input")
    }

    // Check for inline datum (Babbage+)
    if let datumOption = utxo.output.datumOption {
        switch datumOption.datum {
        case .data(let pd):
            return pd
        case .datumHash(let dh):
            // Inline datum option contains a hash — fall through to hash lookup
            if let witnessData = transaction.transactionWitnessSet.plutusData {
                for pd in witnessData.asList {
                    let pdHash = try datumHash(datum: Datum.plutusData(pd))
                    if pdHash.payload == dh.payload {
                        return pd
                    }
                }
            }
            throw MachineError.typeError("findDatum: datum hash from datumOption not found in witness set")
        }
    }

    // Check for datum hash — look it up in the witness set's plutusData
    if let dh = utxo.output.datumHash {
        if let witnessData = transaction.transactionWitnessSet.plutusData {
            for pd in witnessData.asList {
                let pdHash = try datumHash(datum: Datum.plutusData(pd))
                if pdHash.payload == dh.payload {
                    return pd
                }
            }
        }
        throw MachineError.typeError("findDatum: datum hash \(dh.payload.map { String(format: "%02x", $0) }.joined()) not found in witness set")
    }

    throw MachineError.typeError("findDatum: no datum attached to spent UTxO")
}
