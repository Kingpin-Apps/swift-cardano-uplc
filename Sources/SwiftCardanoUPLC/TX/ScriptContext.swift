import Foundation
import OrderedCollections
import SwiftCardanoCore

/// Builds the `ScriptContext` PlutusData argument passed to each validator script.
/// Version-sensitive: V1 (Alonzo), V2 (Babbage/Vasil), V3 (Conway).
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

// MARK: — TxInfo construction (V2)

private func buildTxInfo(
    transaction: Transaction,
    resolvedInputs: [UTxO],
    version: PlutusVersion
) throws -> PlutusData {
    let body = transaction.transactionBody

    // Inputs
    let inputSet = Set(body.inputs.asArray.map { "\($0.transactionId.payload.hexString)#\($0.index)" })
    let inputs = PlutusData.array(try resolvedInputs.compactMap { utxo -> PlutusData? in
        let key = "\(utxo.input.transactionId.payload.hexString)#\(utxo.input.index)"
        guard inputSet.contains(key) else { return nil }
        return try txInInfoData(utxo: utxo)
    })

    // Reference inputs (V2+)
    let refInputs = PlutusData.array([])

    // Outputs
    let outputs = PlutusData.array(try body.outputs.map { try txOutData($0) })

    // Fee
    let fee = PlutusData.constructor(Constr(tag: 0, fields: [
        .constructor(Constr(tag: 0, fields: [.bigInt(.int(Int64(body.fee)))]))
    ]))

    // Mint (simplified — empty)
    let mint = PlutusData.map([:])

    // DCert (empty)
    let dcert = PlutusData.array([])

    // Withdrawals (empty)
    let wdrl = PlutusData.map([:])

    // ValidRange (full range — from -∞ to +∞)
    let validRange = buildFullRange()

    // Signatories
    let signatories = PlutusData.array(try (body.requiredSigners?.asList ?? []).map {
        PlutusData.bytes(try Bytes(from: $0.payload))
    })

    // Redeemers / Datums (empty)
    let redeemers = PlutusData.map([:])
    let datums   = PlutusData.map([:])

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
        return .constructor(Constr(tag: 0, fields: [
            inputs, refInputs, outputs, fee, mint, dcert, wdrl, validRange, signatories, redeemers, datums, txId
        ]))
    }
}

private func txInInfoData(utxo: UTxO) throws -> PlutusData {
    let txId = PlutusData.constructor(Constr(tag: 0, fields: [
        .bytes(try Bytes(from: utxo.input.transactionId.payload))
    ]))
    let idx = PlutusData.bigInt(.int(Int64(utxo.input.index)))
    let outRef = PlutusData.constructor(Constr(tag: 0, fields: [txId, idx]))
    let out = try txOutData(utxo.output)
    return .constructor(Constr(tag: 0, fields: [outRef, out]))
}

private func txOutData(_ output: TransactionOutput) throws -> PlutusData {
    let addrBytes = try output.address.toCBORData()
    let addr  = PlutusData.bytes(try Bytes(from: addrBytes))
    let value = PlutusData.map([:])  // Simplified — full impl converts MultiAsset
    return .constructor(Constr(tag: 0, fields: [addr, value]))
}

private func buildFullRange() -> PlutusData {
    let negInf = PlutusData.constructor(Constr(tag: 0, fields: []))  // NegInf
    let posInf = PlutusData.constructor(Constr(tag: 2, fields: []))  // PosInf
    let from = PlutusData.constructor(Constr(tag: 0, fields: [negInf,
        .constructor(Constr(tag: 1, fields: []))]))  // LowerBound (NegInf, Closed)
    let to = PlutusData.constructor(Constr(tag: 1, fields: [posInf,
        .constructor(Constr(tag: 1, fields: []))]))  // UpperBound (PosInf, Closed)
    return .constructor(Constr(tag: 0, fields: [from, to]))
}

// MARK: — Data extension helper

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
