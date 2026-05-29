import Foundation
import OrderedCollections
import SwiftCardanoCore
import SwiftNaCl

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

// MARK: — TxInfo construction

private func buildTxInfo(
    transaction: Transaction,
    resolvedInputs: [UTxO],
    version: PlutusVersion
) throws -> PlutusData {
    let body = transaction.transactionBody

    // Inputs — resolved UTxOs in Plutus canonical order (sorted by txId bytes then index)
    let sortedTxInputs = body.inputs.asArray.sorted {
        if $0.transactionId.payload != $1.transactionId.payload {
            return $0.transactionId.payload.lexicographicallyPrecedes($1.transactionId.payload)
        }
        return $0.index < $1.index
    }
    let inputs = PlutusData.array(try sortedTxInputs.compactMap { txInput -> PlutusData? in
        let key = "\(txInput.transactionId.payload.hexString)#\(txInput.index)"
        guard let utxo = resolvedInputs.first(where: {
            "\($0.input.transactionId.payload.hexString)#\($0.input.index)" == key
        }) else { return nil }
        return try txInInfoData(utxo: utxo, version: version)
    })

    // Reference inputs (V2+) — TODO: resolve reference inputs when supported
    let refInputs = PlutusData.array([])

    // Outputs — in declaration order
    let outputs = PlutusData.array(try body.outputs.map { try txOutData($0, version: version) })

    // Fee as a lovelace-only Value: Map { b"" => Map { b"" => fee } }
    let fee = valueDataFromCoin(Int(body.fee))

    // Mint — policy tokens only (no ADA entry; ADA cannot be minted)
    let mint: PlutusData
    if let mintedAssets = body.mint {
        mint = mintValueData(mintedAssets)
    } else {
        mint = .map([:])
    }

    // DCert — empty (certificate support not yet implemented)
    let dcert = PlutusData.array([])

    // Withdrawals — empty
    let wdrl: PlutusData = .map([:])

    // ValidRange — full open range; slot→POSIX conversion requires era data not available here
    let validRange = buildFullRange()

    // Signatories
    let signatories = PlutusData.array(try (body.requiredSigners?.asList ?? []).map {
        PlutusData.bytes(try Bytes(from: $0.payload))
    })

    // Datums from witness set: Map { DatumHash bytes => PlutusData }
    let datums = try buildDatumsMap(witnesses: transaction.transactionWitnessSet)

    // Redeemers — empty map (TODO: populate full redeemer map for V2+)
    let redeemers: PlutusData = .map([:])

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

    for (policyId, asset) in txValue.multiAsset.data {
        let csKey = PlutusData.bytes(.byteString(ByteString(bytes: policyId.payload)))
        var tokenMap = OrderedDictionary<PlutusData, PlutusData>()
        for (assetName, amount) in asset.data {
            let tnKey = PlutusData.bytes(.byteString(ByteString(bytes: assetName.payload)))
            tokenMap[tnKey] = .bigInt(.int(Int64(amount)))
        }
        map[csKey] = .map(tokenMap)
    }

    return .map(map)
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
    for (policyId, asset) in multiAsset.data {
        let csKey = PlutusData.bytes(.byteString(ByteString(bytes: policyId.payload)))
        var tokenMap = OrderedDictionary<PlutusData, PlutusData>()
        for (assetName, amount) in asset.data {
            let tnKey = PlutusData.bytes(.byteString(ByteString(bytes: assetName.payload)))
            tokenMap[tnKey] = .bigInt(.int(Int64(amount)))
        }
        map[csKey] = .map(tokenMap)
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
