import Foundation
import OrderedCollections
import SwiftCardanoCore
import SwiftNaCl

/// Raised when a script context cannot be built.
public enum ScriptContextError: Error, Sendable, Equatable {
    /// The Plutus version's context structure is not implemented.
    case unsupportedVersion(String)
    /// The transaction uses a feature this builder cannot encode faithfully.
    ///
    /// Raised rather than silently emitting an empty or approximate field: a
    /// context that is subtly wrong makes a correct script look broken, which
    /// is far harder to diagnose than an explicit refusal.
    case unsupportedFeature(String)
}

/// Builds the `ScriptContext` PlutusData argument passed to each validator script.
/// Version-sensitive: V1 (Alonzo), V2 (Babbage/Vasil), V3 (Conway).
///
/// - Note: V3 is not implemented. See the `.v3` case in `buildTxInfo`.
public struct ScriptContextBuilder: Sendable {
    public init() {}

    /// Build ScriptContext for a spending script.
    public func spendingContext(
        transaction: Transaction,
        spentInput: TransactionInput,
        resolvedInputs: [UTxO],
        version: PlutusVersion = .v2
    ) throws -> PlutusData {
        let txInfo = try buildTxInfo(transaction: transaction, resolvedInputs: resolvedInputs, version: version)
        let purpose = try buildSpendingPurpose(input: spentInput)
        return buildScriptContext(txInfo: txInfo, purpose: purpose)
    }

    /// Build ScriptContext for a minting script.
    public func mintingContext(
        transaction: Transaction,
        resolvedInputs: [UTxO],
        policyId: Data,
        version: PlutusVersion = .v2
    ) throws -> PlutusData {
        let txInfo = try buildTxInfo(transaction: transaction, resolvedInputs: resolvedInputs, version: version)
        let purpose = try buildMintingPurpose(policyId: policyId)
        return buildScriptContext(txInfo: txInfo, purpose: purpose)
    }

    /// Build ScriptContext for a reward-withdrawal script (V1/V2).
    public func rewardingContext(
        transaction: Transaction,
        resolvedInputs: [UTxO],
        stakeCredentialHash: Data,
        isScript: Bool = true,
        version: PlutusVersion = .v2
    ) throws -> PlutusData {
        let txInfo = try buildTxInfo(
            transaction: transaction, resolvedInputs: resolvedInputs, version: version
        )
        let credential = try credentialData(hash: stakeCredentialHash, isScript: isScript)
        // Rewarding wraps the credential in StakingHash.
        let purpose = PlutusData.constructor(Constr(tag: 2, fields: [
            .constructor(Constr(tag: 0, fields: [credential]))
        ]))
        return buildScriptContext(txInfo: txInfo, purpose: purpose)
    }

    // MARK: - PlutusV3

    /// Build the PlutusV3 `ScriptContext` for a spending script.
    ///
    /// `ScriptContext = Constr 0 [TxInfo, Redeemer, ScriptInfo]`, where the
    /// spending `ScriptInfo` carries the output reference *and* the datum —
    /// which is why a V3 script takes a single argument instead of three.
    public func spendingContextV3(
        transaction: Transaction,
        spentInput: TransactionInput,
        resolvedInputs: [UTxO],
        redeemer: PlutusData,
        datum: PlutusData?
    ) throws -> PlutusData {
        let txInfo = try buildTxInfoV3(transaction: transaction, resolvedInputs: resolvedInputs)
        let scriptInfo = PlutusData.constructor(Constr(tag: 1, fields: [
            try outputReferenceV3(spentInput),
            maybeData(datum),
        ]))
        return .constructor(Constr(tag: 0, fields: [txInfo, redeemer, scriptInfo]))
    }

    /// Build the PlutusV3 `ScriptContext` for a reward-withdrawal script.
    ///
    /// V3's `ScriptInfo` names this purpose `Withdrawing` and keys it by the
    /// bare `Credential`, where V1/V2 wrap it in `StakingHash`.
    public func rewardingContextV3(
        transaction: Transaction,
        resolvedInputs: [UTxO],
        stakeCredentialHash: Data,
        isScript: Bool = true,
        redeemer: PlutusData
    ) throws -> PlutusData {
        let txInfo = try buildTxInfoV3(transaction: transaction, resolvedInputs: resolvedInputs)
        let scriptInfo = PlutusData.constructor(Constr(tag: 2, fields: [
            try credentialData(hash: stakeCredentialHash, isScript: isScript)
        ]))
        return .constructor(Constr(tag: 0, fields: [txInfo, redeemer, scriptInfo]))
    }

    /// Build the PlutusV3 `ScriptContext` for a minting script.
    public func mintingContextV3(
        transaction: Transaction,
        resolvedInputs: [UTxO],
        policyId: Data,
        redeemer: PlutusData
    ) throws -> PlutusData {
        let txInfo = try buildTxInfoV3(transaction: transaction, resolvedInputs: resolvedInputs)
        let scriptInfo = PlutusData.constructor(Constr(tag: 0, fields: [
            .bytes(try Bytes(from: policyId))
        ]))
        return .constructor(Constr(tag: 0, fields: [txInfo, redeemer, scriptInfo]))
    }
}

// MARK: — ScriptContext construction

private func buildScriptContext(txInfo: PlutusData, purpose: PlutusData) -> PlutusData {
    .constructor(Constr(tag: 0, fields: [txInfo, purpose]))
}

private func buildSpendingPurpose(input: TransactionInput) throws -> PlutusData {
    let txId = PlutusData.constructor(Constr(tag: 0, fields: [
        .bytes(try Bytes(from: input.transactionId.payload))
    ]))
    let idx = PlutusData.bigInt(.int(Int64(input.index)))
    let txInInfo = PlutusData.constructor(Constr(tag: 0, fields: [txId, idx]))
    return .constructor(Constr(tag: 1, fields: [txInInfo]))  // Spending
}

private func buildMintingPurpose(policyId: Data) throws -> PlutusData {
    let cs = PlutusData.bytes(try Bytes(from: policyId))
    return .constructor(Constr(tag: 0, fields: [cs]))  // Minting
}

// MARK: — TxInfo construction

private func buildTxInfo(
    transaction: Transaction,
    resolvedInputs: [UTxO],
    version: PlutusVersion
) throws -> PlutusData {
    let body = transaction.transactionBody

    // Refuse what cannot be encoded faithfully rather than substituting an
    // empty value, which silently changes what the script sees.
    if let certificates = body.certificates, certificates.count > 0 {
        throw ScriptContextError.unsupportedFeature(
            "Transactions with certificates are not supported in the script context yet."
        )
    }
    if body.ttl != nil || body.validityStart != nil {
        throw ScriptContextError.unsupportedFeature(
            "Transactions with a validity interval are not supported in the script context yet: "
            + "converting slots to POSIX time needs era history that is not available here."
        )
    }

    // Inputs — resolved UTxOs in Plutus canonical order (sorted by txId bytes then index).
    // An input that cannot be resolved is an error: dropping it hands the
    // script a transaction that spends less than it really does.
    let inputs = dataList(
        try resolvedInputsData(for: body.inputs.asArray, resolvedInputs: resolvedInputs, version: version)
    )

    // Reference inputs (V2+).
    let refInputs = dataList(
        version == .v1
            ? []
            : try resolvedInputsData(
                for: body.referenceInputs?.asList ?? [],
                resolvedInputs: resolvedInputs,
                version: version
            )
    )

    // Outputs — in declaration order
    let outputs = dataList(try body.outputs.map { try txOutData($0, version: version) })

    // Fee as a lovelace-only Value: Map { b"" => Map { b"" => fee } }
    let fee = valueDataFromCoin(Int(body.fee))

    // Mint — policy tokens only (no ADA entry; ADA cannot be minted)
    let mint: PlutusData
    if let mintedAssets = body.mint {
        mint = mintValueData(mintedAssets)
    } else {
        mint = .map([:])
    }

    // DCert — certificates are refused above, so this is genuinely empty.
    let dcert = dataList([])

    // Withdrawals: `Map StakingCredential Integer` in V1/V2 (V3 keys these by
    // `Credential` instead).
    let wdrl = try withdrawalsDataV1V2(body.withdrawals)

    // ValidRange — full open range; slot→POSIX conversion requires era data not available here
    let validRange = buildFullRange()

    // Signatories
    let signatories = dataList(try (body.requiredSigners?.asList ?? []).map {
        PlutusData.bytes(try Bytes(from: $0.payload))
    })

    // Datums from witness set: Map { DatumHash bytes => PlutusData }
    let datums = try buildDatumsMap(witnesses: transaction.transactionWitnessSet)

    // Redeemers: `Map ScriptPurpose Redeemer`. V1 has no such field.
    let redeemers: PlutusData = version == .v1
        ? .map([:])
        : try redeemersMapV1V2(transaction: transaction)

    // TxId
    let txId = PlutusData.constructor(Constr(tag: 0, fields: [
        .bytes(try Bytes(from: body.id.payload))
    ]))

    switch version {
    case .v1:
        return .constructor(Constr(tag: 0, fields: [
            inputs, outputs, fee, mint, dcert, wdrl, validRange, signatories, datums, txId
        ]))
    case .v2:
        return .constructor(Constr(tag: 0, fields: [
            inputs, refInputs, outputs, fee, mint, dcert, wdrl, validRange, signatories, redeemers, datums, txId
        ]))
    case .v3:
        // V3 does not share this structure at all — it is built by
        // `buildTxInfoV3`. Reaching here means a caller routed a V3 script
        // through the V1/V2 path.
        throw ScriptContextError.unsupportedVersion(
            "PlutusV3 transaction info is built by buildTxInfoV3, not the V1/V2 path."
        )
    }
}

// MARK: — PlutusV3 TxInfo

/// Build the PlutusV3 `TxInfo`: a 16-field record.
///
/// Field order (from the ledger's V3 script context):
///   inputs, reference_inputs, outputs, fee, mint, certificates, withdrawals,
///   validity_range, extra_signatories, redeemers, datums, id, votes,
///   proposal_procedures, current_treasury_amount, treasury_donation
///
/// Differences from V1/V2 that are easy to get wrong:
///   - `fee` is a bare Integer, not a Value
///   - `id` is a raw ByteString, not `Constr 0 [ByteString]`
///   - an `OutputReference`'s transaction id is likewise raw bytes
///   - `mint` never contains a lovelace entry
private func buildTxInfoV3(
    transaction: Transaction,
    resolvedInputs: [UTxO]
) throws -> PlutusData {
    let body = transaction.transactionBody

    // Anything this builder cannot encode faithfully is refused rather than
    // approximated — see `ScriptContextError.unsupportedFeature`.
    if let certificates = body.certificates, certificates.count > 0 {
        throw ScriptContextError.unsupportedFeature(
            "Transactions with certificates are not supported in the V3 script context yet."
        )
    }
    if let votes = body.votingProcedures, !votes.isEmpty {
        throw ScriptContextError.unsupportedFeature(
            "Transactions with voting procedures are not supported in the V3 script context yet."
        )
    }
    if let proposals = body.proposalProcedures, proposals.count > 0 {
        throw ScriptContextError.unsupportedFeature(
            "Transactions with proposal procedures are not supported in the V3 script context yet."
        )
    }
    if body.ttl != nil || body.validityStart != nil {
        // The script context carries POSIX milliseconds, not slots. Converting
        // needs the era history and genesis parameters, which this builder is
        // not given — emitting the unbounded interval instead would quietly
        // defeat every deadline check in the script.
        throw ScriptContextError.unsupportedFeature(
            "Transactions with a validity interval are not supported in the V3 script context yet: "
            + "converting slots to POSIX time needs era history that is not available here."
        )
    }

    let inputs = dataList(
        try resolvedInputsData(for: body.inputs.asArray, resolvedInputs: resolvedInputs)
    )
    let referenceInputs = dataList(
        try resolvedInputsData(for: body.referenceInputs?.asList ?? [], resolvedInputs: resolvedInputs)
    )

    let outputs = dataList(try body.outputs.map { try txOutData($0, version: .v3) })

    // Lovelace is a bare integer in V3, not a Value.
    let fee = PlutusData.bigInt(.int(Int64(body.fee)))

    let mint = body.mint.map { mintValueData($0) } ?? .map([:])

    let certificates = dataList([])
    let withdrawals = try withdrawalsDataV3(body.withdrawals)
    let validRange = buildFullRange()

    let signatories = dataList(try (body.requiredSigners?.asList ?? []).map {
        PlutusData.bytes(try Bytes(from: $0.payload))
    })

    let redeemers = try redeemersMapV3(transaction: transaction)
    let datums = try buildDatumsMap(witnesses: transaction.transactionWitnessSet)

    // Raw bytes in V3, not Constr 0 [bytes].
    let txId = PlutusData.bytes(try Bytes(from: body.id.payload))

    let votes = PlutusData.map([:])
    let proposals = dataList([])
    let treasuryAmount = maybeData(body.currentTreasuryAmount.map { .bigInt(.int(Int64($0))) })
    let treasuryDonation = maybeData(body.treasuryDonation.map { .bigInt(.int(Int64($0.value))) })

    return .constructor(Constr(tag: 0, fields: [
        inputs, referenceInputs, outputs, fee, mint, certificates, withdrawals,
        validRange, signatories, redeemers, datums, txId, votes, proposals,
        treasuryAmount, treasuryDonation,
    ]))
}

/// Resolve a list of transaction inputs to `Input` values, in the ledger's
/// canonical order (transaction id bytes, then output index).
///
/// An input that is not in the resolved set is an error rather than an
/// omission: a script handed a shorter input list sees a different
/// transaction from the one being validated.
private func resolvedInputsData(
    for inputs: [TransactionInput],
    resolvedInputs: [UTxO],
    version: PlutusVersion = .v3
) throws -> [PlutusData] {
    let sorted = inputs.sorted {
        if $0.transactionId.payload != $1.transactionId.payload {
            return $0.transactionId.payload.lexicographicallyPrecedes($1.transactionId.payload)
        }
        return $0.index < $1.index
    }
    return try sorted.map { input in
        guard let utxo = resolvedInputs.first(where: {
            $0.input.transactionId.payload == input.transactionId.payload
                && $0.input.index == input.index
        }) else {
            throw ScriptContextError.unsupportedFeature(
                "Input \(input.transactionId.payload.hexString)#\(input.index) is not in the "
                + "resolved UTxO set, so the script context would be missing it."
            )
        }
        if version == .v3 {
            return .constructor(Constr(tag: 0, fields: [
                try outputReferenceV3(utxo.input),
                try txOutData(utxo.output, version: version),
            ]))
        }
        return try txInInfoData(utxo: utxo, version: version)
    }
}

/// `withdrawals: Map StakingCredential Integer` for V1/V2.
///
/// V1/V2 wrap the credential in `StakingHash`; V3 keys the map by the bare
/// `Credential` instead.
private func withdrawalsDataV1V2(_ withdrawals: Withdrawals?) throws -> PlutusData {
    let entries = orderedWithdrawalCredentials(withdrawals)
    guard !entries.isEmpty else { return .map([:]) }
    var map = OrderedDictionary<PlutusData, PlutusData>()
    for entry in entries {
        let credential = try credentialData(hash: entry.hash, isScript: entry.isScript)
        map[.constructor(Constr(tag: 0, fields: [credential]))] = .bigInt(.int(entry.amount))
    }
    return .map(map)
}

/// `redeemers: Map ScriptPurpose Redeemer` for V2.
///
/// The V1/V2 `ScriptPurpose` has four constructors — Minting, Spending,
/// Rewarding, Certifying — and `Spending` wraps a V1/V2 `TxOutRef`, whose
/// transaction id is itself wrapped in `Constr 0`.
private func redeemersMapV1V2(transaction: Transaction) throws -> PlutusData {
    let body = transaction.transactionBody
    guard let redeemers = transaction.transactionWitnessSet.redeemers else { return .map([:]) }

    var flattened: [(tag: RedeemerTag?, index: Int, data: PlutusData)] = []
    switch redeemers {
    case .list(let list):
        flattened = list.map { ($0.tag, $0.index, $0.data) }
    case .map(let map):
        flattened = map.pairs.map { ($0.key.tag, $0.key.index, $0.value.data) }
    }

    let sortedInputs = body.inputs.asArray.sorted {
        if $0.transactionId.payload != $1.transactionId.payload {
            return $0.transactionId.payload.lexicographicallyPrecedes($1.transactionId.payload)
        }
        return $0.index < $1.index
    }
    let sortedPolicies = (body.mint.map { Array($0.data.keys) } ?? []).sorted {
        $0.payload.lexicographicallyPrecedes($1.payload)
    }

    var pairs: [(purposeTag: Int, key: PlutusData, value: PlutusData)] = []
    for entry in flattened {
        switch entry.tag {
        case .spend:
            guard entry.index < sortedInputs.count else {
                throw ScriptContextError.unsupportedFeature(
                    "Spend redeemer index \(entry.index) is out of range for the transaction's inputs."
                )
            }
            let input = sortedInputs[entry.index]
            let txId = PlutusData.constructor(Constr(tag: 0, fields: [
                .bytes(try Bytes(from: input.transactionId.payload))
            ]))
            let outRef = PlutusData.constructor(Constr(tag: 0, fields: [
                txId, .bigInt(.int(Int64(input.index)))
            ]))
            pairs.append((1, .constructor(Constr(tag: 1, fields: [outRef])), entry.data))
        case .mint:
            guard entry.index < sortedPolicies.count else {
                throw ScriptContextError.unsupportedFeature(
                    "Mint redeemer index \(entry.index) is out of range for the transaction's mint field."
                )
            }
            let purpose = PlutusData.constructor(Constr(tag: 0, fields: [
                .bytes(try Bytes(from: sortedPolicies[entry.index].payload))
            ]))
            pairs.append((0, purpose, entry.data))
        case .reward:
            let entries = orderedWithdrawalCredentials(body.withdrawals)
            guard entry.index < entries.count else {
                throw ScriptContextError.unsupportedFeature(
                    "Reward redeemer index \(entry.index) is out of range for the transaction's withdrawals."
                )
            }
            let credential = entries[entry.index]
            let inner = try credentialData(hash: credential.hash, isScript: credential.isScript)
            let purpose = PlutusData.constructor(Constr(tag: 2, fields: [
                .constructor(Constr(tag: 0, fields: [inner]))
            ]))
            pairs.append((2, purpose, entry.data))
        default:
            throw ScriptContextError.unsupportedFeature(
                "Redeemer purpose \(String(describing: entry.tag)) is not supported in the "
                + "script context yet."
            )
        }
    }

    let sorted = try pairs.sorted { lhs, rhs in
        if lhs.purposeTag != rhs.purposeTag { return lhs.purposeTag < rhs.purposeTag }
        return try lhs.key.toCBORData().lexicographicallyPrecedes(rhs.key.toCBORData())
    }

    var map = OrderedDictionary<PlutusData, PlutusData>()
    for pair in sorted { map[pair.key] = pair.value }
    return .map(map)
}

/// `OutputReference { transaction_id: ByteString, output_index: Int }`.
/// The transaction id is raw bytes in V3 — V1/V2 wrap it in `Constr 0`.
private func outputReferenceV3(_ input: TransactionInput) throws -> PlutusData {
    .constructor(Constr(tag: 0, fields: [
        .bytes(try Bytes(from: input.transactionId.payload)),
        .bigInt(.int(Int64(input.index))),
    ]))
}

/// A `Data` list in the ledger's canonical form.
///
/// Plutus encodes a `Data` list — and a constructor's fields — as an
/// *indefinite-length* CBOR array when it is non-empty, and as a definite
/// empty array otherwise. Building lists the definite way produces a value
/// that serialises differently from the one the ledger would hand the script,
/// and that compares unequal to a list decoded from a datum.
func dataList(_ items: [PlutusData]) -> PlutusData {
    items.isEmpty ? .array([]) : .indefiniteArray(IndefiniteList(items))
}

/// A withdrawal's reward credential, in the ledger's order.
///
/// A reward address is a one-byte header followed by the credential; bit 4 of
/// the header is set when that credential is a script. The ledger orders
/// reward accounts by credential, and its `Credential` places script hashes
/// *before* key hashes — a redeemer's `reward` index counts through this same
/// order, so every consumer has to agree on it.
struct WithdrawalCredential: Sendable {
    let isScript: Bool
    let hash: Data
    let amount: Int64
}

func orderedWithdrawalCredentials(_ withdrawals: Withdrawals?) -> [WithdrawalCredential] {
    guard let withdrawals else { return [] }
    var entries: [WithdrawalCredential] = []
    for (rewardAccount, coin) in withdrawals.data {
        guard let header = rewardAccount.first else { continue }
        entries.append(WithdrawalCredential(
            isScript: (header & 0x10) != 0,
            hash: Data(rewardAccount.dropFirst()),
            amount: Int64(coin)
        ))
    }
    return entries.sorted {
        if $0.isScript != $1.isScript { return $0.isScript }
        return $0.hash.lexicographicallyPrecedes($1.hash)
    }
}

/// `Credential` — `VerificationKey` is constructor 0, `Script` is 1.
private func credentialData(hash: Data, isScript: Bool) throws -> PlutusData {
    .constructor(Constr(tag: isScript ? 1 : 0, fields: [.bytes(try Bytes(from: hash))]))
}

/// `withdrawals: Pairs<Credential, Lovelace>` for V3.
private func withdrawalsDataV3(_ withdrawals: Withdrawals?) throws -> PlutusData {
    let entries = orderedWithdrawalCredentials(withdrawals)
    guard !entries.isEmpty else { return .map([:]) }
    var map = OrderedDictionary<PlutusData, PlutusData>()
    for entry in entries {
        map[try credentialData(hash: entry.hash, isScript: entry.isScript)] =
            .bigInt(.int(entry.amount))
    }
    return .map(map)
}

/// `redeemers: Pairs<ScriptPurpose, Redeemer>`, ordered by ascending purpose.
private func redeemersMapV3(transaction: Transaction) throws -> PlutusData {
    let body = transaction.transactionBody
    guard let redeemers = transaction.transactionWitnessSet.redeemers else { return .map([:]) }

    var flattened: [(tag: RedeemerTag?, index: Int, data: PlutusData)] = []
    switch redeemers {
    case .list(let list):
        flattened = list.map { ($0.tag, $0.index, $0.data) }
    case .map(let map):
        flattened = map.pairs.map { ($0.key.tag, $0.key.index, $0.value.data) }
    }

    let sortedInputs = body.inputs.asArray.sorted {
        if $0.transactionId.payload != $1.transactionId.payload {
            return $0.transactionId.payload.lexicographicallyPrecedes($1.transactionId.payload)
        }
        return $0.index < $1.index
    }
    let sortedPolicies = (body.mint.map { Array($0.data.keys) } ?? []).sorted {
        $0.payload.lexicographicallyPrecedes($1.payload)
    }

    var pairs: [(purposeTag: Int, key: PlutusData, value: PlutusData)] = []
    for entry in flattened {
        switch entry.tag {
        case .spend:
            guard entry.index < sortedInputs.count else {
                throw ScriptContextError.unsupportedFeature(
                    "Spend redeemer index \(entry.index) is out of range for the transaction's inputs."
                )
            }
            let purpose = PlutusData.constructor(Constr(tag: 1, fields: [
                try outputReferenceV3(sortedInputs[entry.index])
            ]))
            pairs.append((1, purpose, entry.data))
        case .mint:
            guard entry.index < sortedPolicies.count else {
                throw ScriptContextError.unsupportedFeature(
                    "Mint redeemer index \(entry.index) is out of range for the transaction's mint field."
                )
            }
            let purpose = PlutusData.constructor(Constr(tag: 0, fields: [
                .bytes(try Bytes(from: sortedPolicies[entry.index].payload))
            ]))
            pairs.append((0, purpose, entry.data))
        case .reward:
            let entries = orderedWithdrawalCredentials(body.withdrawals)
            guard entry.index < entries.count else {
                throw ScriptContextError.unsupportedFeature(
                    "Reward redeemer index \(entry.index) is out of range for the transaction's withdrawals."
                )
            }
            let credential = entries[entry.index]
            let purpose = PlutusData.constructor(Constr(tag: 2, fields: [
                try credentialData(hash: credential.hash, isScript: credential.isScript)
            ]))
            pairs.append((2, purpose, entry.data))
        default:
            throw ScriptContextError.unsupportedFeature(
                "Redeemer purpose \(String(describing: entry.tag)) is not supported in the "
                + "V3 script context yet."
            )
        }
    }

    // ScriptPurpose ordering follows the constructor order (Minting, Spending,
    // Rewarding, Certifying, Voting, Proposing), then the encoded payload.
    let sorted = try pairs.sorted { lhs, rhs in
        if lhs.purposeTag != rhs.purposeTag { return lhs.purposeTag < rhs.purposeTag }
        return try lhs.key.toCBORData().lexicographicallyPrecedes(rhs.key.toCBORData())
    }

    var map = OrderedDictionary<PlutusData, PlutusData>()
    for pair in sorted { map[pair.key] = pair.value }
    return .map(map)
}

/// `Option<a>` — `Some` is constructor 0, `None` is constructor 1.
private func maybeData(_ value: PlutusData?) -> PlutusData {
    guard let value else { return .constructor(Constr(tag: 1, fields: [])) }
    return .constructor(Constr(tag: 0, fields: [value]))
}

// MARK: — TxInInfo / TxOut helpers

private func txInInfoData(utxo: UTxO, version: PlutusVersion) throws -> PlutusData {
    let txId = PlutusData.constructor(Constr(tag: 0, fields: [
        .bytes(try Bytes(from: utxo.input.transactionId.payload))
    ]))
    let idx = PlutusData.bigInt(.int(Int64(utxo.input.index)))
    let outRef = PlutusData.constructor(Constr(tag: 0, fields: [txId, idx]))
    let out = try txOutData(utxo.output, version: version)
    return .constructor(Constr(tag: 0, fields: [outRef, out]))
}

/// Encode a `TransactionOutput` as TxOut PlutusData.
///
/// - V1: `Constr(0, [address, value, Maybe DatumHash])`
/// - V2/V3: `Constr(0, [address, value, OutputDatum, Maybe ScriptHash])`
private func txOutData(_ output: TransactionOutput, version: PlutusVersion) throws -> PlutusData {
    let addr  = try addressData(output.address)
    let value = valueData(output.amount)

    switch version {
    case .v1:
        let maybeDatumHash = outputMaybeDatumHashV1(output)
        return .constructor(Constr(tag: 0, fields: [addr, value, maybeDatumHash]))
    case .v2, .v3:
        let outputDatum    = outputDatumV2(output)
        let maybeRefScript = try outputMaybeRefScript(output)
        return .constructor(Constr(tag: 0, fields: [addr, value, outputDatum, maybeRefScript]))
    }
}

/// V1 datum field: `Maybe DatumHash` — `Nothing = Constr(1,[])`, `Just h = Constr(0,[h])`
private func outputMaybeDatumHashV1(_ output: TransactionOutput) -> PlutusData {
    if case .datumHash(let dh) = output.datumOption?.datum {
        return .constructor(Constr(tag: 0, fields: [.bytes(.byteString(ByteString(bytes: dh.payload)))]))
    }
    if let dh = output.datumHash {
        return .constructor(Constr(tag: 0, fields: [.bytes(.byteString(ByteString(bytes: dh.payload)))]))
    }
    return .constructor(Constr(tag: 1, fields: []))  // Nothing
}

/// V2 datum field: `NoOutputDatum(0)`, `OutputDatumHash(1,[h])`, `OutputDatum(2,[d])`
private func outputDatumV2(_ output: TransactionOutput) -> PlutusData {
    if let datumOption = output.datumOption {
        switch datumOption.datum {
        case .data(let pd):
            return .constructor(Constr(tag: 2, fields: [pd]))
        case .datumHash(let dh):
            return .constructor(Constr(tag: 1, fields: [.bytes(.byteString(ByteString(bytes: dh.payload)))]))
        }
    }
    if let dh = output.datumHash {
        return .constructor(Constr(tag: 1, fields: [.bytes(.byteString(ByteString(bytes: dh.payload)))]))
    }
    return .constructor(Constr(tag: 0, fields: []))  // NoOutputDatum
}

/// V2 reference-script field: `Nothing = Constr(1,[])`, `Just h = Constr(0,[h])`
private func outputMaybeRefScript(_ output: TransactionOutput) throws -> PlutusData {
    if let script = output.script, let sh = try? scriptHash(script: script) {
        return .constructor(Constr(tag: 0, fields: [.bytes(.byteString(ByteString(bytes: sh.payload)))]))
    }
    return .constructor(Constr(tag: 1, fields: []))  // Nothing
}

// MARK: — Address encoding

/// Encode a Cardano address as Plutus `Address`:
/// `Constr(0, [PaymentCredential, Maybe StakingCredential])`
private func addressData(_ address: Address) throws -> PlutusData {
    let paymentCred: PlutusData
    switch address.paymentPart {
    case .verificationKeyHash(let vkh):
        paymentCred = .constructor(Constr(tag: 0, fields: [.bytes(.byteString(ByteString(bytes: vkh.payload)))]))
    case .scriptHash(let sh):
        paymentCred = .constructor(Constr(tag: 1, fields: [.bytes(.byteString(ByteString(bytes: sh.payload)))]))
    case nil:
        paymentCred = .constructor(Constr(tag: 0, fields: [.bytes(.byteString(ByteString(bytes: Data())))]))
    }

    let stakingCred: PlutusData
    switch address.stakingPart {
    case .verificationKeyHash(let vkh):
        let innerCred = PlutusData.constructor(Constr(tag: 0, fields: [.bytes(.byteString(ByteString(bytes: vkh.payload)))]))
        let sc = PlutusData.constructor(Constr(tag: 0, fields: [innerCred]))
        stakingCred = .constructor(Constr(tag: 0, fields: [sc]))
    case .scriptHash(let sh):
        let innerCred = PlutusData.constructor(Constr(tag: 1, fields: [.bytes(.byteString(ByteString(bytes: sh.payload)))]))
        let sc = PlutusData.constructor(Constr(tag: 0, fields: [innerCred]))
        stakingCred = .constructor(Constr(tag: 0, fields: [sc]))
    case .pointerAddress(let ptr):
        let sc = PlutusData.constructor(Constr(tag: 1, fields: [
            .bigInt(.int(Int64(ptr.slot))),
            .bigInt(.int(Int64(ptr.txIndex))),
            .bigInt(.int(Int64(ptr.certIndex)))
        ]))
        stakingCred = .constructor(Constr(tag: 0, fields: [sc]))
    case nil:
        stakingCred = .constructor(Constr(tag: 1, fields: []))  // Nothing
    }

    return .constructor(Constr(tag: 0, fields: [paymentCred, stakingCred]))
}

// MARK: — Value encoding

/// Encode a Cardano transaction value (coin + multi-asset) as a PlutusData Value `Map`:
/// `Map { currencySymbol => Map { tokenName => amount } }`
private func valueData(_ txValue: SwiftCardanoCore.Value) -> PlutusData {
    let adaKey = PlutusData.bytes(.byteString(ByteString(bytes: Data())))
    let tnKey  = PlutusData.bytes(.byteString(ByteString(bytes: Data())))
    var adaInner = OrderedDictionary<PlutusData, PlutusData>()
    adaInner[tnKey] = .bigInt(.int(Int64(txValue.coin)))
    var map = OrderedDictionary<PlutusData, PlutusData>()
    map[adaKey] = .map(adaInner)

    for (policyId, asset) in canonicalAssets(txValue.multiAsset) {
        let csKey = PlutusData.bytes(.byteString(ByteString(bytes: policyId.payload)))
        map[csKey] = .map(tokenMap(for: asset))
    }

    return .map(map)
}

/// A multi-asset's policies in canonical order.
///
/// `MultiAsset.data` is a Swift `Dictionary`, whose iteration order is
/// arbitrary and randomised per process. A Plutus `Value` is a map, and the
/// ledger builds it with its policies and asset names in ascending bytewise
/// order — a script folding over one, or comparing two, sees a different value
/// if the order differs.
private func canonicalAssets(_ multiAsset: MultiAsset) -> [(ScriptHash, SwiftCardanoCore.Asset)] {
    multiAsset.data
        .map { ($0.key, $0.value) }
        .sorted { $0.0.payload.lexicographicallyPrecedes($1.0.payload) }
}

/// One policy's token map, in canonical asset-name order.
private func tokenMap(for asset: SwiftCardanoCore.Asset) -> OrderedDictionary<PlutusData, PlutusData> {
    var tokens = OrderedDictionary<PlutusData, PlutusData>()
    let sorted = asset.data
        .map { ($0.key, $0.value) }
        .sorted { $0.0.payload.lexicographicallyPrecedes($1.0.payload) }
    for (assetName, amount) in sorted {
        tokens[.bytes(.byteString(ByteString(bytes: assetName.payload)))] = .bigInt(.int(Int64(amount)))
    }
    return tokens
}

/// Encode a lovelace-only Value (for fee): `Map { b"" => Map { b"" => coin } }`
private func valueDataFromCoin(_ coin: Int) -> PlutusData {
    let adaKey = PlutusData.bytes(.byteString(ByteString(bytes: Data())))
    let tnKey  = PlutusData.bytes(.byteString(ByteString(bytes: Data())))
    var adaInner = OrderedDictionary<PlutusData, PlutusData>()
    adaInner[tnKey] = .bigInt(.int(Int64(coin)))
    var map = OrderedDictionary<PlutusData, PlutusData>()
    map[adaKey] = .map(adaInner)
    return .map(map)
}

/// Encode a `MultiAsset` (the mint field) as a Plutus Value map — no ADA entry.
private func mintValueData(_ multiAsset: MultiAsset) -> PlutusData {
    var map = OrderedDictionary<PlutusData, PlutusData>()
    for (policyId, asset) in canonicalAssets(multiAsset) {
        let csKey = PlutusData.bytes(.byteString(ByteString(bytes: policyId.payload)))
        map[csKey] = .map(tokenMap(for: asset))
    }
    return .map(map)
}

// MARK: — Datums map

/// Build `txInfoData`: `Map { DatumHash => Datum }` from the transaction witness set.
private func buildDatumsMap(witnesses: TransactionWitnessSet) throws -> PlutusData {
    var map = OrderedDictionary<PlutusData, PlutusData>()
    for pd in witnesses.plutusData?.asList ?? [] {
        if let cborData = try? pd.toCBORData(),
           let hashBytes = try? Hash().blake2b(data: cborData, digestSize: 32, encoder: RawEncoder.self) {
            let hashKey = PlutusData.bytes(.byteString(ByteString(bytes: hashBytes)))
            map[hashKey] = pd
        }
    }
    return .map(map)
}

// MARK: — ValidRange

private func buildFullRange() -> PlutusData {
    let negInf = PlutusData.constructor(Constr(tag: 0, fields: []))  // NegInf
    let posInf = PlutusData.constructor(Constr(tag: 2, fields: []))  // PosInf
    // Both bounds are single-constructor records, so both are Constr 0.
    // The upper bound used to be emitted as Constr 1, which made every
    // validity-range check in a script read a malformed interval.
    let closed = PlutusData.constructor(Constr(tag: 1, fields: []))  // True
    let from = PlutusData.constructor(Constr(tag: 0, fields: [negInf, closed]))
    let to = PlutusData.constructor(Constr(tag: 0, fields: [posInf, closed]))
    return .constructor(Constr(tag: 0, fields: [from, to]))
}

// MARK: — Data extension helper

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
