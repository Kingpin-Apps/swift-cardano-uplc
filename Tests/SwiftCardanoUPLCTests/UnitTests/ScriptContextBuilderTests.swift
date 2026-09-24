import Testing
import Foundation
import OrderedCollections
import SwiftCardanoCore
@testable import SwiftCardanoUPLC

// MARK: — PlutusData navigation helpers

private extension PlutusData {
    /// Constructor tag, or nil if this is not a constructor.
    var constrTag: UInt64? {
        if case .constructor(let c) = self { return c.tag }
        return nil
    }
    /// Constructor fields, or nil if this is not a constructor.
    var constrFields: [PlutusData]? {
        if case .constructor(let c) = self { return c.fields }
        return nil
    }
    /// A `Data` list, in either representation: the builder emits the
    /// ledger's canonical indefinite form for non-empty lists.
    var arrayItems: [PlutusData]? {
        switch self {
        case .array(let items):           return items
        case .indefiniteArray(let items): return items.getAll()
        default:                          return nil
        }
    }
    var mapEntries: OrderedDictionary<PlutusData, PlutusData>? {
        if case .map(let m) = self { return m }
        return nil
    }
    var bytesData: Data? {
        if case .bytes(let b) = self { return b.data }
        return nil
    }
    var intValue: Int64? {
        if case .bigInt(let n) = self { return n.intValue }
        return nil
    }
}

// MARK: — Fixtures

private let emptyBytes = PlutusData.bytes(.byteString(ByteString(bytes: Data())))

private func scriptAddress(_ byte: UInt8 = 0xAB) throws -> Address {
    try Address(
        paymentPart: .scriptHash(ScriptHash(payload: Data(repeating: byte, count: SCRIPT_HASH_SIZE))),
        stakingPart: nil,
        network: .testnet
    )
}

private func vkeyAddress(_ byte: UInt8 = 0x11) throws -> Address {
    try Address(
        paymentPart: .verificationKeyHash(VerificationKeyHash(payload: Data(repeating: byte, count: VERIFICATION_KEY_HASH_SIZE))),
        stakingPart: nil,
        network: .testnet
    )
}

private func txInput(_ idByte: UInt8 = 0x01, index: UInt16 = 0) -> TransactionInput {
    TransactionInput(
        transactionId: TransactionId(payload: Data(repeating: idByte, count: TRANSACTION_HASH_SIZE)),
        index: index
    )
}

/// A spendable UTxO at a script address holding `coin` lovelace.
private func scriptUTxO(
    _ idByte: UInt8 = 0x01,
    coin: Int64 = 2_000_000,
    datumOption: DatumOption? = nil,
    addrByte: UInt8 = 0xAB
) throws -> UTxO {
    let output = TransactionOutput(
        address: try scriptAddress(addrByte),
        amount: Value(coin: coin),
        datumOption: datumOption
    )
    return UTxO(input: txInput(idByte), output: output)
}

@Suite("ScriptContextBuilder — spending & minting contexts")
struct ScriptContextBuilderTests {

    // MARK: — Top-level ScriptContext shape

    @Test("spending context is Constr(0, [txInfo, purpose])")
    func spendingContext_topLevelShape() throws {
        let input = txInput()
        let utxo = try scriptUTxO()
        let body = TransactionBody(inputs: .list([input]), outputs: [], fee: 0)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try ScriptContextBuilder().spendingContext(
            transaction: tx, spentInput: input, resolvedInputs: [utxo], version: .v2
        )

        #expect(ctx.constrTag == 0)
        #expect(ctx.constrFields?.count == 2)
    }

    @Test("spending purpose is Spending(Constr 1) wrapping the spent outRef")
    func spendingContext_purposeIsSpending() throws {
        let input = txInput(0x07, index: 3)
        let utxo = try scriptUTxO(0x07)
        // Output's input must match the spent input for it to resolve.
        let resolvedUTxO = UTxO(input: input, output: utxo.output)
        let body = TransactionBody(inputs: .list([input]), outputs: [], fee: 0)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try ScriptContextBuilder().spendingContext(
            transaction: tx, spentInput: input, resolvedInputs: [resolvedUTxO], version: .v2
        )

        let purpose = try #require(ctx.constrFields?[1])
        #expect(purpose.constrTag == 1)  // Spending
        let txInInfo = try #require(purpose.constrFields?.first)
        #expect(txInInfo.constrTag == 0)
        // [ txId-constr, index ]
        let txIdConstr = try #require(txInInfo.constrFields?[0])
        #expect(txIdConstr.constrTag == 0)
        #expect(txIdConstr.constrFields?.first?.bytesData == Data(repeating: 0x07, count: TRANSACTION_HASH_SIZE))
        #expect(txInInfo.constrFields?[1].intValue == 3)
    }

    @Test("minting purpose is Minting(Constr 0) wrapping the policy id")
    func mintingContext_purposeIsMinting() throws {
        let policyId = Data(repeating: 0xCC, count: SCRIPT_HASH_SIZE)
        let body = TransactionBody(inputs: .list([txInput()]), outputs: [], fee: 0)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try ScriptContextBuilder().mintingContext(
            transaction: tx, resolvedInputs: [try scriptUTxO()], policyId: policyId, version: .v2
        )

        let purpose = try #require(ctx.constrFields?[1])
        #expect(purpose.constrTag == 0)  // Minting
        #expect(purpose.constrFields?.first?.bytesData == policyId)
    }

    // MARK: — TxInfo field counts per version

    @Test("V1 TxInfo has 10 fields, V2 has 12")
    func txInfo_fieldCountsByVersion() throws {
        let input = txInput()
        let utxo = try scriptUTxO()
        let body = TransactionBody(inputs: .list([input]), outputs: [], fee: 0)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
        let builder = ScriptContextBuilder()

        let v1 = try builder.spendingContext(transaction: tx, spentInput: input, resolvedInputs: [utxo], version: .v1)
        let v2 = try builder.spendingContext(transaction: tx, spentInput: input, resolvedInputs: [utxo], version: .v2)

        #expect(v1.constrFields?[0].constrFields?.count == 10)
        #expect(v2.constrFields?[0].constrFields?.count == 12)
    }

    /// V3's ScriptContext is structurally different from V1/V2, so the V1/V2
    /// entry point must refuse it rather than emitting the V2 shape — which
    /// produced a context every V3 validator rejects, reading as "your script
    /// failed". V3 has its own entry points.
    @Test("the V1/V2 entry point refuses V3 instead of emitting the V2 shape")
    func txInfo_v3IsExplicitlyUnsupported() throws {
        let input = txInput()
        let utxo = try scriptUTxO()
        let body = TransactionBody(inputs: .list([input]), outputs: [], fee: 0)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        #expect(throws: ScriptContextError.self) {
            try ScriptContextBuilder().spendingContext(
                transaction: tx, spentInput: input, resolvedInputs: [utxo], version: .v3
            )
        }
    }

    // MARK: — Inputs list

    @Test("resolved inputs appear in the TxInfo inputs list")
    func txInfo_inputsResolved() throws {
        let input = txInput()
        let utxo = try scriptUTxO()
        let body = TransactionBody(inputs: .list([input]), outputs: [], fee: 0)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try ScriptContextBuilder().spendingContext(
            transaction: tx, spentInput: input, resolvedInputs: [utxo], version: .v2
        )
        let inputs = try #require(ctx.constrFields?[0].constrFields?[0].arrayItems)
        #expect(inputs.count == 1)
        // Each TxInInfo is Constr(0, [outRef, txOut])
        #expect(inputs[0].constrTag == 0)
        #expect(inputs[0].constrFields?.count == 2)
    }

    /// An unresolved input used to be silently omitted, handing the script a
    /// transaction that spends less than the real one — a script checking
    /// "how much came in" would read the wrong total and still be told it had
    /// the real context.
    @Test("an unresolved input is refused rather than dropped")
    func txInfo_unresolvedInputRefused() throws {
        let input = txInput()
        let body = TransactionBody(inputs: .list([input]), outputs: [], fee: 0)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        #expect(throws: ScriptContextError.self) {
            try ScriptContextBuilder().spendingContext(
                transaction: tx, spentInput: input, resolvedInputs: [], version: .v2
            )
        }
    }

    // MARK: — Fee encoding

    @Test("fee is encoded as a lovelace-only Value map")
    func txInfo_feeEncoding() throws {
        let input = txInput()
        let utxo = try scriptUTxO()
        let body = TransactionBody(inputs: .list([input]), outputs: [], fee: 170_000)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try ScriptContextBuilder().spendingContext(
            transaction: tx, spentInput: input, resolvedInputs: [utxo], version: .v2
        )
        // V2 fee is field index 3.
        let fee = try #require(ctx.constrFields?[0].constrFields?[3])
        let outerMap = try #require(fee.mapEntries)
        let adaInner = try #require(outerMap[emptyBytes]?.mapEntries)
        #expect(adaInner[emptyBytes]?.intValue == 170_000)
    }

    // MARK: — Mint encoding

    @Test("empty mint is an empty map")
    func txInfo_emptyMint() throws {
        let input = txInput()
        let utxo = try scriptUTxO()
        let body = TransactionBody(inputs: .list([input]), outputs: [], fee: 0)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try ScriptContextBuilder().spendingContext(
            transaction: tx, spentInput: input, resolvedInputs: [utxo], version: .v2
        )
        let mint = try #require(ctx.constrFields?[0].constrFields?[4])
        #expect(mint.mapEntries?.isEmpty == true)
    }

    @Test("mint field carries policy and token amounts, no ADA entry")
    func txInfo_mintWithAssets() throws {
        let policyId = ScriptHash(payload: Data(repeating: 0xCC, count: SCRIPT_HASH_SIZE))
        let assetName = AssetName(from: "TOKEN")
        let asset = Asset([assetName: 42])
        let mintAsset = MultiAsset([policyId: asset])

        let input = txInput()
        let utxo = try scriptUTxO()
        let body = TransactionBody(inputs: .list([input]), outputs: [], fee: 0, mint: mintAsset)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try ScriptContextBuilder().spendingContext(
            transaction: tx, spentInput: input, resolvedInputs: [utxo], version: .v2
        )
        let mint = try #require(ctx.constrFields?[0].constrFields?[4].mapEntries)
        let csKey = PlutusData.bytes(.byteString(ByteString(bytes: policyId.payload)))
        // No ADA (empty) key in mint.
        #expect(mint[emptyBytes] == nil)
        let tokenMap = try #require(mint[csKey]?.mapEntries)
        let tnKey = PlutusData.bytes(.byteString(ByteString(bytes: assetName.payload)))
        #expect(tokenMap[tnKey]?.intValue == 42)
    }

    // MARK: — Signatories

    @Test("required signers are encoded as signatory bytes")
    func txInfo_signatories() throws {
        let signer = VerificationKeyHash(payload: Data(repeating: 0x55, count: VERIFICATION_KEY_HASH_SIZE))
        let input = txInput()
        let utxo = try scriptUTxO()
        let body = TransactionBody(
            inputs: .list([input]), outputs: [], fee: 0,
            requiredSigners: .list([signer])
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try ScriptContextBuilder().spendingContext(
            transaction: tx, spentInput: input, resolvedInputs: [utxo], version: .v2
        )
        // V2 signatories are field index 8.
        let signatories = try #require(ctx.constrFields?[0].constrFields?[8].arrayItems)
        #expect(signatories.count == 1)
        #expect(signatories[0].bytesData == signer.payload)
    }

    // MARK: — Outputs / value encoding

    @Test("output value encodes coin under the empty currency symbol and token name")
    func txOut_valueEncoding() throws {
        let input = txInput()
        let utxo = try scriptUTxO(coin: 5_000_000)
        let output = TransactionOutput(address: try vkeyAddress(), amount: Value(coin: 5_000_000))
        let body = TransactionBody(inputs: .list([input]), outputs: [output], fee: 0)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try ScriptContextBuilder().spendingContext(
            transaction: tx, spentInput: input, resolvedInputs: [utxo], version: .v2
        )
        // V2 outputs are field index 2.
        let outputs = try #require(ctx.constrFields?[0].constrFields?[2].arrayItems)
        #expect(outputs.count == 1)
        // TxOut = Constr(0, [addr, value, outputDatum, maybeRefScript])
        let txOut = outputs[0]
        #expect(txOut.constrFields?.count == 4)
        let value = try #require(txOut.constrFields?[1].mapEntries)
        let adaInner = try #require(value[emptyBytes]?.mapEntries)
        #expect(adaInner[emptyBytes]?.intValue == 5_000_000)
    }

    // MARK: — Address encoding

    @Test("script payment credential uses Constr tag 1; no staking is Nothing")
    func address_scriptPaymentNoStaking() throws {
        let input = txInput()
        let utxo = try scriptUTxO(addrByte: 0x99)
        let output = TransactionOutput(address: try scriptAddress(0x99), amount: Value(coin: 1))
        let body = TransactionBody(inputs: .list([input]), outputs: [output], fee: 0)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try ScriptContextBuilder().spendingContext(
            transaction: tx, spentInput: input, resolvedInputs: [utxo], version: .v2
        )
        let outputs = try #require(ctx.constrFields?[0].constrFields?[2].arrayItems)
        let addr = try #require(outputs[0].constrFields?[0])
        // Address = Constr(0, [paymentCred, maybeStakingCred])
        let paymentCred = try #require(addr.constrFields?[0])
        #expect(paymentCred.constrTag == 1)  // ScriptCredential
        #expect(paymentCred.constrFields?.first?.bytesData == Data(repeating: 0x99, count: SCRIPT_HASH_SIZE))
        let stakingCred = try #require(addr.constrFields?[1])
        #expect(stakingCred.constrTag == 1)  // Nothing
    }

    @Test("vkey payment credential uses Constr tag 0")
    func address_vkeyPayment() throws {
        let input = txInput()
        let utxo = try scriptUTxO()
        let output = TransactionOutput(address: try vkeyAddress(0x22), amount: Value(coin: 1))
        let body = TransactionBody(inputs: .list([input]), outputs: [output], fee: 0)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try ScriptContextBuilder().spendingContext(
            transaction: tx, spentInput: input, resolvedInputs: [utxo], version: .v2
        )
        let outputs = try #require(ctx.constrFields?[0].constrFields?[2].arrayItems)
        let paymentCred = try #require(outputs[0].constrFields?[0].constrFields?[0])
        #expect(paymentCred.constrTag == 0)  // PubKeyCredential
        #expect(paymentCred.constrFields?.first?.bytesData == Data(repeating: 0x22, count: VERIFICATION_KEY_HASH_SIZE))
    }

    // MARK: — Output datum (V2)

    @Test("V2 output with no datum is NoOutputDatum (Constr 0)")
    func txOut_v2_noDatum() throws {
        let input = txInput()
        let utxo = try scriptUTxO()
        let output = TransactionOutput(address: try vkeyAddress(), amount: Value(coin: 1))
        let body = TransactionBody(inputs: .list([input]), outputs: [output], fee: 0)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try ScriptContextBuilder().spendingContext(
            transaction: tx, spentInput: input, resolvedInputs: [utxo], version: .v2
        )
        let outputs = try #require(ctx.constrFields?[0].constrFields?[2].arrayItems)
        let outputDatum = try #require(outputs[0].constrFields?[2])
        #expect(outputDatum.constrTag == 0)  // NoOutputDatum
        #expect(outputDatum.constrFields?.isEmpty == true)
    }

    @Test("V2 output with inline datum is OutputDatum (Constr 2)")
    func txOut_v2_inlineDatum() throws {
        let inlineDatum = PlutusData.bigInt(.int(99))
        let input = txInput()
        let utxo = try scriptUTxO()
        let output = TransactionOutput(
            address: try vkeyAddress(),
            amount: Value(coin: 1),
            datumOption: DatumOption(datum: inlineDatum)
        )
        let body = TransactionBody(inputs: .list([input]), outputs: [output], fee: 0)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try ScriptContextBuilder().spendingContext(
            transaction: tx, spentInput: input, resolvedInputs: [utxo], version: .v2
        )
        let outputs = try #require(ctx.constrFields?[0].constrFields?[2].arrayItems)
        let outputDatum = try #require(outputs[0].constrFields?[2])
        #expect(outputDatum.constrTag == 2)  // OutputDatum
        #expect(outputDatum.constrFields?.first?.intValue == 99)
    }

    @Test("V2 output with datum hash is OutputDatumHash (Constr 1)")
    func txOut_v2_datumHash() throws {
        let dh = DatumHash(payload: Data(repeating: 0x44, count: DATUM_HASH_SIZE))
        let input = txInput()
        let utxo = try scriptUTxO()
        let output = TransactionOutput(
            address: try vkeyAddress(),
            amount: Value(coin: 1),
            datumOption: DatumOption(datum: dh)
        )
        let body = TransactionBody(inputs: .list([input]), outputs: [output], fee: 0)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try ScriptContextBuilder().spendingContext(
            transaction: tx, spentInput: input, resolvedInputs: [utxo], version: .v2
        )
        let outputs = try #require(ctx.constrFields?[0].constrFields?[2].arrayItems)
        let outputDatum = try #require(outputs[0].constrFields?[2])
        #expect(outputDatum.constrTag == 1)  // OutputDatumHash
        #expect(outputDatum.constrFields?.first?.bytesData == dh.payload)
    }

    // MARK: — Output datum (V1)

    @Test("V1 output with no datum hash is Nothing (Constr 1)")
    func txOut_v1_noDatumHash() throws {
        let input = txInput()
        let utxo = try scriptUTxO()
        let output = TransactionOutput(address: try vkeyAddress(), amount: Value(coin: 1))
        let body = TransactionBody(inputs: .list([input]), outputs: [output], fee: 0)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try ScriptContextBuilder().spendingContext(
            transaction: tx, spentInput: input, resolvedInputs: [utxo], version: .v1
        )
        // V1 outputs are field index 1; TxOut = Constr(0, [addr, value, maybeDatumHash])
        let outputs = try #require(ctx.constrFields?[0].constrFields?[1].arrayItems)
        let txOut = outputs[0]
        #expect(txOut.constrFields?.count == 3)
        let maybeDatumHash = try #require(txOut.constrFields?[2])
        #expect(maybeDatumHash.constrTag == 1)  // Nothing
    }

    @Test("V1 output with a datum hash is Just(Constr 0)")
    func txOut_v1_withDatumHash() throws {
        let dh = DatumHash(payload: Data(repeating: 0x66, count: DATUM_HASH_SIZE))
        let input = txInput()
        let utxo = try scriptUTxO()
        let output = TransactionOutput(
            address: try vkeyAddress(),
            amount: Value(coin: 1),
            datumOption: DatumOption(datum: dh)
        )
        let body = TransactionBody(inputs: .list([input]), outputs: [output], fee: 0)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try ScriptContextBuilder().spendingContext(
            transaction: tx, spentInput: input, resolvedInputs: [utxo], version: .v1
        )
        let outputs = try #require(ctx.constrFields?[0].constrFields?[1].arrayItems)
        let maybeDatumHash = try #require(outputs[0].constrFields?[2])
        #expect(maybeDatumHash.constrTag == 0)  // Just
        #expect(maybeDatumHash.constrFields?.first?.bytesData == dh.payload)
    }

    // MARK: — ValidRange

    @Test("valid range is the full open interval (-inf, +inf)")
    func txInfo_validRangeIsFull() throws {
        let input = txInput()
        let utxo = try scriptUTxO()
        let body = TransactionBody(inputs: .list([input]), outputs: [], fee: 0)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try ScriptContextBuilder().spendingContext(
            transaction: tx, spentInput: input, resolvedInputs: [utxo], version: .v2
        )
        // V2 validRange is field index 7. Interval = Constr(0, [lowerBound, upperBound])
        let validRange = try #require(ctx.constrFields?[0].constrFields?[7])
        #expect(validRange.constrTag == 0)
        let lower = try #require(validRange.constrFields?[0])  // LowerBound(NegInf, Closed)
        #expect(lower.constrFields?[0].constrTag == 0)  // NegInf
        let upper = try #require(validRange.constrFields?[1])  // UpperBound(PosInf, Closed)
        #expect(upper.constrFields?[0].constrTag == 2)  // PosInf
    }

    // MARK: — Datums map from witness set

    @Test("witness-set datums populate the datums map keyed by hash")
    func txInfo_datumsMap() throws {
        let datum = PlutusData.bigInt(.int(7))
        let input = txInput()
        let utxo = try scriptUTxO()
        let body = TransactionBody(inputs: .list([input]), outputs: [], fee: 0)
        let witnesses = TransactionWitnessSet(plutusData: .list([datum]))
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnesses)

        let ctx = try ScriptContextBuilder().spendingContext(
            transaction: tx, spentInput: input, resolvedInputs: [utxo], version: .v2
        )
        // V2 datums are field index 10.
        let datums = try #require(ctx.constrFields?[0].constrFields?[10].mapEntries)
        #expect(datums.count == 1)
        // The single value is the original datum.
        #expect(datums.values.first?.intValue == 7)
    }

    @Test("empty witness set yields an empty datums map")
    func txInfo_emptyDatumsMap() throws {
        let input = txInput()
        let utxo = try scriptUTxO()
        let body = TransactionBody(inputs: .list([input]), outputs: [], fee: 0)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try ScriptContextBuilder().spendingContext(
            transaction: tx, spentInput: input, resolvedInputs: [utxo], version: .v2
        )
        let datums = try #require(ctx.constrFields?[0].constrFields?[10].mapEntries)
        #expect(datums.isEmpty)
    }
}


// MARK: — PlutusV3 script context

/// PlutusV3's context is a different structure from V1/V2, and the differences
/// are all silent ones — a wrong shape does not fail to build, it just makes
/// every validator reject the transaction.
@Suite("PlutusV3 ScriptContext")
struct ScriptContextV3Tests {

    private func redeemerData() -> PlutusData { .bigInt(.int(42)) }

    private func fixture(
        referenceInputs: ListOrNonEmptyOrderedSet<TransactionInput>? = nil,
        certificates: ListOrNonEmptyOrderedSet<Certificate>? = nil,
        ttl: SlotNumber? = nil
    ) throws -> (tx: Transaction, spent: TransactionInput, utxos: [UTxO]) {
        let spent = txInput(0x01)
        let utxo = try scriptUTxO(0x01)
        var body = TransactionBody(
            inputs: .list([spent]),
            outputs: [TransactionOutput(address: try vkeyAddress(), amount: Value(coin: 1_000_000))],
            fee: 175_000
        )
        body.referenceInputs = referenceInputs
        body.certificates = certificates
        body.ttl = ttl

        var redeemerMap = RedeemerMap()
        redeemerMap[RedeemerKey(tag: .spend, index: 0)] = RedeemerValue(
            data: redeemerData(), exUnits: ExecutionUnits(mem: 1, steps: 1)
        )
        let tx = Transaction(
            transactionBody: body,
            transactionWitnessSet: TransactionWitnessSet(redeemers: .map(redeemerMap))
        )
        return (tx, spent, [utxo])
    }

    @Test("ScriptContext is Constr 0 with TxInfo, redeemer and ScriptInfo")
    func contextHasThreeFields() throws {
        let f = try fixture()
        let ctx = try ScriptContextBuilder().spendingContextV3(
            transaction: f.tx, spentInput: f.spent, resolvedInputs: f.utxos,
            redeemer: redeemerData(), datum: nil
        )
        #expect(ctx.constrTag == 0)
        #expect(ctx.constrFields?.count == 3)
        #expect(ctx.constrFields?[1].intValue == 42)  // the redeemer itself
    }

    @Test("TxInfo has 16 fields")
    func txInfoHasSixteenFields() throws {
        let f = try fixture()
        let ctx = try ScriptContextBuilder().spendingContextV3(
            transaction: f.tx, spentInput: f.spent, resolvedInputs: f.utxos,
            redeemer: redeemerData(), datum: nil
        )
        #expect(ctx.constrFields?[0].constrFields?.count == 16)
    }

    @Test("fee is a bare integer, not a Value map")
    func feeIsInteger() throws {
        let f = try fixture()
        let ctx = try ScriptContextBuilder().spendingContextV3(
            transaction: f.tx, spentInput: f.spent, resolvedInputs: f.utxos,
            redeemer: redeemerData(), datum: nil
        )
        let fee = try #require(ctx.constrFields?[0].constrFields?[3])
        #expect(fee.intValue == 175_000)
        #expect(fee.mapEntries == nil)
    }

    @Test("transaction id is raw bytes, not Constr 0 [bytes]")
    func txIdIsRawBytes() throws {
        let f = try fixture()
        let ctx = try ScriptContextBuilder().spendingContextV3(
            transaction: f.tx, spentInput: f.spent, resolvedInputs: f.utxos,
            redeemer: redeemerData(), datum: nil
        )
        let id = try #require(ctx.constrFields?[0].constrFields?[11])
        #expect(id.bytesData != nil)
        #expect(id.constrTag == nil)
    }

    @Test("an OutputReference's transaction id is raw bytes too")
    func outputReferenceUsesRawBytes() throws {
        let f = try fixture()
        let ctx = try ScriptContextBuilder().spendingContextV3(
            transaction: f.tx, spentInput: f.spent, resolvedInputs: f.utxos,
            redeemer: redeemerData(), datum: nil
        )
        let firstInput = try #require(ctx.constrFields?[0].constrFields?[0].arrayItems?.first)
        let outRef = try #require(firstInput.constrFields?[0])
        #expect(outRef.constrFields?[0].bytesData == Data(repeating: 0x01, count: TRANSACTION_HASH_SIZE))
        #expect(outRef.constrFields?[0].constrTag == nil)
        #expect(outRef.constrFields?[1].intValue == 0)
    }

    @Test("spending ScriptInfo is Constr 1 carrying the output reference and datum")
    func spendingScriptInfoCarriesDatum() throws {
        let f = try fixture()
        let datum = PlutusData.bigInt(.int(7))
        let ctx = try ScriptContextBuilder().spendingContextV3(
            transaction: f.tx, spentInput: f.spent, resolvedInputs: f.utxos,
            redeemer: redeemerData(), datum: datum
        )
        let info = try #require(ctx.constrFields?[2])
        #expect(info.constrTag == 1)
        #expect(info.constrFields?.count == 2)
        // Some(datum)
        #expect(info.constrFields?[1].constrTag == 0)
        #expect(info.constrFields?[1].constrFields?.first?.intValue == 7)
    }

    @Test("a missing datum is None, not an empty Some")
    func missingDatumIsNone() throws {
        let f = try fixture()
        let ctx = try ScriptContextBuilder().spendingContextV3(
            transaction: f.tx, spentInput: f.spent, resolvedInputs: f.utxos,
            redeemer: redeemerData(), datum: nil
        )
        #expect(ctx.constrFields?[2].constrFields?[1].constrTag == 1)
    }

    @Test("minting ScriptInfo is Constr 0 wrapping the policy id")
    func mintingScriptInfo() throws {
        let f = try fixture()
        let policyId = Data(repeating: 0xCC, count: SCRIPT_HASH_SIZE)
        let ctx = try ScriptContextBuilder().mintingContextV3(
            transaction: f.tx, resolvedInputs: f.utxos,
            policyId: policyId, redeemer: redeemerData()
        )
        let info = try #require(ctx.constrFields?[2])
        #expect(info.constrTag == 0)
        #expect(info.constrFields?.first?.bytesData == policyId)
    }

    @Test("reference inputs are resolved into the context, not left empty")
    func referenceInputsArePopulated() throws {
        let reference = txInput(0x02)
        let referenceUTxO = try scriptUTxO(0x02, addrByte: 0xCD)
        var f = try fixture(referenceInputs: .list([reference]))
        f.utxos.append(referenceUTxO)

        let ctx = try ScriptContextBuilder().spendingContextV3(
            transaction: f.tx, spentInput: f.spent, resolvedInputs: f.utxos,
            redeemer: redeemerData(), datum: nil
        )
        let refs = try #require(ctx.constrFields?[0].constrFields?[1].arrayItems)
        #expect(refs.count == 1)
        #expect(refs[0].constrFields?[0].constrFields?[0].bytesData
                == Data(repeating: 0x02, count: TRANSACTION_HASH_SIZE))
    }

    @Test("the redeemers map is keyed by ScriptPurpose")
    func redeemersMapIsKeyedByPurpose() throws {
        let f = try fixture()
        let ctx = try ScriptContextBuilder().spendingContextV3(
            transaction: f.tx, spentInput: f.spent, resolvedInputs: f.utxos,
            redeemer: redeemerData(), datum: nil
        )
        let redeemers = try #require(ctx.constrFields?[0].constrFields?[9].mapEntries)
        #expect(redeemers.count == 1)
        let purpose = try #require(redeemers.keys.first)
        #expect(purpose.constrTag == 1)  // Spend
        #expect(redeemers.values.first?.intValue == 42)
    }

    // MARK: - Refusals

    @Test("a transaction with a validity interval is refused, not given an unbounded range")
    func validityIntervalIsRefused() throws {
        let f = try fixture(ttl: 1_000)
        #expect(throws: ScriptContextError.self) {
            try ScriptContextBuilder().spendingContextV3(
                transaction: f.tx, spentInput: f.spent, resolvedInputs: f.utxos,
                redeemer: redeemerData(), datum: nil
            )
        }
    }

    @Test("an unresolved input is refused rather than dropped from the context")
    func unresolvedInputIsRefused() throws {
        let f = try fixture()
        #expect(throws: ScriptContextError.self) {
            try ScriptContextBuilder().spendingContextV3(
                transaction: f.tx, spentInput: f.spent, resolvedInputs: [],
                redeemer: redeemerData(), datum: nil
            )
        }
    }
}

// MARK: — Interval encoding

@Suite("Validity range encoding")
struct ValidityRangeTests {

    /// Both interval bounds are single-constructor records, so both are
    /// `Constr 0`. The upper bound was emitted as `Constr 1`, which made every
    /// validity-range check in a script read a malformed interval.
    @Test("both interval bounds are Constr 0")
    func bothBoundsAreConstrZero() throws {
        let spent = txInput()
        let utxo = try scriptUTxO()
        let body = TransactionBody(inputs: .list([spent]), outputs: [], fee: 0)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try ScriptContextBuilder().spendingContext(
            transaction: tx, spentInput: spent, resolvedInputs: [utxo], version: .v2
        )
        // V2 TxInfo: inputs, refInputs, outputs, fee, mint, dcert, wdrl,
        // validRange, ...
        let range = try #require(ctx.constrFields?[0].constrFields?[7])
        #expect(range.constrTag == 0)
        #expect(range.constrFields?[0].constrTag == 0)  // lower bound
        #expect(range.constrFields?[1].constrTag == 0)  // upper bound
    }
}

// MARK: — Reward withdrawals

/// A reward redeemer's index counts through the transaction's withdrawals in
/// the ledger's reward-account order, which places script credentials before
/// key credentials. `findScript`, the redeemers map and the withdrawals field
/// all have to agree on that order.
@Suite("Reward withdrawal script purposes")
struct RewardPurposeTests {

    private func rewardAccount(_ byte: UInt8, isScript: Bool) -> Data {
        Data([isScript ? 0xF1 : 0xE1]) + Data(repeating: byte, count: SCRIPT_HASH_SIZE)
    }

    private func withdrawals(_ entries: [(UInt8, Bool, Int)]) -> Withdrawals {
        var map = OrderedDictionary<RewardAccount, Coin>()
        for (byte, isScript, amount) in entries {
            map[rewardAccount(byte, isScript: isScript)] = Coin(amount)
        }
        return Withdrawals(map)
    }

    @Test("script credentials are ordered before key credentials")
    func scriptCredentialsSortFirst() {
        // Declared key-first and with a higher hash, so only the ledger's rule
        // produces this order.
        let ordered = orderedWithdrawalCredentials(withdrawals([
            (0x11, false, 5), (0xCC, true, 7), (0x22, true, 9),
        ]))
        #expect(ordered.map(\.isScript) == [true, true, false])
        #expect(ordered.map { $0.hash.first } == [0x22, 0xCC, 0x11])
        #expect(ordered.map(\.amount) == [9, 7, 5])
    }

    @Test("V3 withdrawing ScriptInfo carries the bare credential")
    func v3WithdrawingScriptInfo() throws {
        let body = TransactionBody(
            inputs: .list([txInput()]), outputs: [], fee: 0,
            withdrawals: withdrawals([(0xAA, true, 0)])
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try ScriptContextBuilder().rewardingContextV3(
            transaction: tx, resolvedInputs: [try scriptUTxO()],
            stakeCredentialHash: Data(repeating: 0xAA, count: SCRIPT_HASH_SIZE),
            redeemer: .bigInt(.int(0))
        )
        let info = try #require(ctx.constrFields?[2])
        #expect(info.constrTag == 2)                       // Withdrawing
        #expect(info.constrFields?.first?.constrTag == 1)  // Script credential
        #expect(info.constrFields?.first?.constrFields?.first?.bytesData
                == Data(repeating: 0xAA, count: SCRIPT_HASH_SIZE))
    }

    @Test("V1/V2 rewarding purpose wraps the credential in StakingHash")
    func v1v2RewardingPurpose() throws {
        let body = TransactionBody(
            inputs: .list([txInput()]), outputs: [], fee: 0,
            withdrawals: withdrawals([(0xAA, true, 0)])
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try ScriptContextBuilder().rewardingContext(
            transaction: tx, resolvedInputs: [try scriptUTxO()],
            stakeCredentialHash: Data(repeating: 0xAA, count: SCRIPT_HASH_SIZE),
            version: .v2
        )
        let purpose = try #require(ctx.constrFields?[1])
        #expect(purpose.constrTag == 2)                        // Rewarding
        let staking = try #require(purpose.constrFields?.first)
        #expect(staking.constrTag == 0)                        // StakingHash
        #expect(staking.constrFields?.first?.constrTag == 1)   // Script credential
    }

    @Test("withdrawals appear in the TxInfo keyed by credential")
    func withdrawalsInTxInfo() throws {
        let body = TransactionBody(
            inputs: .list([txInput()]), outputs: [], fee: 0,
            withdrawals: withdrawals([(0x11, false, 5), (0xAA, true, 7)])
        )
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())
        let ctx = try ScriptContextBuilder().rewardingContextV3(
            transaction: tx, resolvedInputs: [try scriptUTxO()],
            stakeCredentialHash: Data(repeating: 0xAA, count: SCRIPT_HASH_SIZE),
            redeemer: .bigInt(.int(0))
        )
        let entries = try #require(ctx.constrFields?[0].constrFields?[6].mapEntries)
        #expect(entries.count == 2)
        // Script credential first.
        #expect(entries.keys.first?.constrTag == 1)
        #expect(entries.values.first?.intValue == 7)
    }
}

// MARK: — Canonical Data encoding

@Suite("Script context Data is canonical")
struct CanonicalContextDataTests {

    /// Plutus writes a non-empty `Data` list as an indefinite-length array and
    /// an empty one as a definite empty array. A list built the definite way
    /// serialises differently from the one the ledger hands the script.
    @Test("non-empty lists are indefinite, empty lists are definite")
    func listEncoding() throws {
        let input = txInput()
        let body = TransactionBody(inputs: .list([input]), outputs: [], fee: 0)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try ScriptContextBuilder().spendingContextV3(
            transaction: tx, spentInput: input, resolvedInputs: [try scriptUTxO()],
            redeemer: .bigInt(.int(0)), datum: nil
        )
        let txInfo = try #require(ctx.constrFields?[0].constrFields)

        if case .indefiniteArray = txInfo[0] {} else {
            Issue.record("non-empty inputs list should be indefinite, got \(txInfo[0])")
        }
        if case .array(let empty) = txInfo[1] { #expect(empty.isEmpty) } else {
            Issue.record("empty reference inputs list should be a definite empty array")
        }
    }

    /// `MultiAsset` is backed by a Swift `Dictionary`, whose order is
    /// arbitrary and randomised per process. A Plutus `Value` is a map the
    /// ledger builds in ascending bytewise order.
    @Test("value maps are ordered by policy then asset name")
    func valueOrdering() throws {
        var multiAsset = MultiAsset([:])
        for policyByte in [UInt8(0xCC), 0x11, 0x77] {
            let policy = try ScriptHash(payload: Data(repeating: policyByte, count: SCRIPT_HASH_SIZE))
            multiAsset[policy] = Asset([
                try AssetName(payload: Data([0x7A])): 1,
                try AssetName(payload: Data([0x0A])): 2,
            ])
        }
        let input = txInput()
        let output = TransactionOutput(
            address: try vkeyAddress(),
            amount: Value(coin: 1_000_000, multiAsset: multiAsset)
        )
        let body = TransactionBody(inputs: .list([input]), outputs: [output], fee: 0)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let ctx = try ScriptContextBuilder().spendingContextV3(
            transaction: tx, spentInput: input, resolvedInputs: [try scriptUTxO()],
            redeemer: .bigInt(.int(0)), datum: nil
        )
        let outputs = try #require(ctx.constrFields?[0].constrFields?[2].arrayItems)
        let value = try #require(outputs[0].constrFields?[1].mapEntries)

        // Lovelace sits under the empty policy, which sorts first.
        let policies = value.keys.map { $0.bytesData?.first }
        #expect(policies == [nil, 0x11, 0x77, 0xCC])

        let tokens = try #require(value.values.dropFirst().first?.mapEntries)
        #expect(tokens.keys.map { $0.bytesData?.first } == [0x0A, 0x7A])
    }
}
