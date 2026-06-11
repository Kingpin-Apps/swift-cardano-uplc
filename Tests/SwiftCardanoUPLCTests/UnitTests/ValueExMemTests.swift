import Testing
import BigInt
import Foundation
import OrderedCollections
import SwiftCardanoCore
@testable import SwiftCardanoUPLC

// MARK: — Value.exMem()

@Suite("Value — exMem memory cost")
struct ValueExMemTests {

    // MARK: — Constructors that always cost 1

    @Test("delay value costs 1 ExMem regardless of contents")
    func delay_costsOne() {
        let value = Value.delay(.constant(.integer(BigInt(99999))), Environment())
        #expect(value.exMem() == 1)
    }

    @Test("lambda value costs 1 ExMem regardless of body")
    func lambda_costsOne() {
        let value = Value.lambda(
            parameterName: NamedDeBruijn(text: "x", index: DeBruijn(0)),
            body: .constant(.integer(BigInt(1))),
            env: Environment()
        )
        #expect(value.exMem() == 1)
    }

    @Test("partiallyApplied value costs 1 ExMem regardless of accumulated args")
    func partiallyApplied_costsOne() {
        let value = Value.partiallyApplied(
            .addInteger,
            [.con(.integer(BigInt(5))), .con(.integer(BigInt(7)))],
            forces: 0
        )
        #expect(value.exMem() == 1)
    }

    // MARK: — con delegates to the constant

    @Test("con value delegates to the wrapped constant's exMem")
    func con_delegatesToConstant() {
        #expect(Value.con(.integer(BigInt(0))).exMem() == 1)
        #expect(Value.con(.unit).exMem() == 1)
        #expect(Value.con(.bool(true)).exMem() == 1)
    }

    // MARK: — constr sums fields and adds 1

    @Test("empty constr costs 1 (just the node)")
    func constr_empty_costsOne() {
        #expect(Value.constr(tag: 0, fields: []).exMem() == 1)
    }

    @Test("constr cost is the sum of field costs plus 1 for the node")
    func constr_sumsFieldsPlusOne() {
        let fields: [SwiftCardanoUPLC.Value] = [
            .con(.integer(BigInt(0))),  // 1
            .con(.integer(BigInt(0))),  // 1
            .delay(Term<NamedDeBruijn>.constant(.unit), Environment())  // 1
        ]
        // 1 + 1 + 1 + 1 (node) == 4
        #expect(Value.constr(tag: 7, fields: fields).exMem() == 4)
    }

    @Test("nested constr accumulates inner field costs")
    func constr_nested() {
        let inner = Value.constr(tag: 0, fields: [.con(.integer(BigInt(0)))])  // 1 + 1 = 2
        let outer = Value.constr(tag: 1, fields: [inner])  // 2 + 1 = 3
        #expect(outer.exMem() == 3)
    }
}

// MARK: — UPLCConstant.exMem()

@Suite("UPLCConstant — exMem memory cost")
struct UPLCConstantExMemTests {

    // MARK: — integer

    @Test("integer zero costs 1")
    func integer_zero() {
        #expect(UPLCConstant.integer(BigInt(0)).exMem() == 1)
    }

    @Test("small integer fits in a single 64-bit word")
    func integer_smallSingleWord() {
        #expect(UPLCConstant.integer(BigInt(1)).exMem() == 1)
        #expect(UPLCConstant.integer(BigInt(-1)).exMem() == 1)
        // Largest magnitude that still fits in 64 bits.
        let maxWord = (BigInt(1) << 64) - 1
        #expect(UPLCConstant.integer(maxWord).exMem() == 1)
    }

    @Test("integer needing a second word costs 2")
    func integer_twoWords() {
        let twoWords = BigInt(1) << 64  // bitWidth 65 → 2 words
        #expect(UPLCConstant.integer(twoWords).exMem() == 2)
    }

    @Test("negative magnitude is measured the same as positive")
    func integer_negativeMagnitude() {
        let twoWords = -(BigInt(1) << 64)
        #expect(UPLCConstant.integer(twoWords).exMem() == 2)
    }

    // MARK: — byteString

    @Test("empty bytestring costs 1")
    func byteString_empty() {
        #expect(UPLCConstant.byteString(Data()).exMem() == 1)
    }

    @Test("bytestring of 1..8 bytes costs 1")
    func byteString_uptoEightBytes() {
        #expect(UPLCConstant.byteString(Data(repeating: 0, count: 1)).exMem() == 1)
        #expect(UPLCConstant.byteString(Data(repeating: 0, count: 8)).exMem() == 1)
    }

    @Test("bytestring of 9 bytes spills into a second word")
    func byteString_nineBytes() {
        #expect(UPLCConstant.byteString(Data(repeating: 0, count: 9)).exMem() == 2)
        #expect(UPLCConstant.byteString(Data(repeating: 0, count: 16)).exMem() == 2)
        #expect(UPLCConstant.byteString(Data(repeating: 0, count: 17)).exMem() == 3)
    }

    // MARK: — string

    @Test("string cost is the number of unicode scalars")
    func string_unicodeScalarCount() {
        #expect(UPLCConstant.string("").exMem() == 0)
        #expect(UPLCConstant.string("hello").exMem() == 5)
        // A single emoji is one unicode scalar.
        #expect(UPLCConstant.string("😀").exMem() == 1)
    }

    // MARK: — unit / bool

    @Test("unit and bool each cost 1")
    func unitAndBool() {
        #expect(UPLCConstant.unit.exMem() == 1)
        #expect(UPLCConstant.bool(false).exMem() == 1)
        #expect(UPLCConstant.bool(true).exMem() == 1)
    }

    // MARK: — list / pair

    @Test("empty list costs 0 (sum of nothing)")
    func list_empty() {
        #expect(UPLCConstant.list(.integer, []).exMem() == 0)
    }

    @Test("list cost is the sum of its element costs")
    func list_sumsElements() {
        let items: [UPLCConstant] = [.integer(BigInt(0)), .integer(BigInt(0)), .unit]
        #expect(UPLCConstant.list(.integer, items).exMem() == 3)
    }

    @Test("pair cost is the sum of both components")
    func pair_sumsComponents() {
        let pair = UPLCConstant.pair(.integer, .bool, .integer(BigInt(0)), .bool(true))
        #expect(pair.exMem() == 2)
    }

    // MARK: — BLS elements (fixed sizes)

    @Test("BLS G1 element costs 6 (48 bytes / 8)")
    func bls_g1() {
        #expect(UPLCConstant.bls12_381G1Element(Data(repeating: 0, count: 48)).exMem() == 6)
    }

    @Test("BLS G2 element costs 12 (96 bytes / 8)")
    func bls_g2() {
        #expect(UPLCConstant.bls12_381G2Element(Data(repeating: 0, count: 96)).exMem() == 12)
    }

    @Test("BLS MlResult costs 72 (576 bytes / 8)")
    func bls_mlResult() {
        #expect(UPLCConstant.bls12_381MlResult(Data(repeating: 0, count: 576)).exMem() == 72)
    }

    // MARK: — data delegates to PlutusData

    @Test("data constant delegates to the PlutusData cost")
    func data_delegates() {
        let pd = PlutusData.constructor(Constr(tag: 0, fields: []))  // 4
        #expect(UPLCConstant.data(pd).exMem() == 4)
    }
}

// MARK: — PlutusData.exMem()

@Suite("PlutusData — exMem memory cost")
struct PlutusDataExMemTests {

    @Test("empty constructor costs 4 (one node)")
    func constructor_empty() {
        #expect(PlutusData.constructor(Constr(tag: 0, fields: [])).exMem() == 4)
    }

    @Test("constructor cost is 4 plus the sum of field costs")
    func constructor_withFields() {
        let pd = PlutusData.constructor(Constr(tag: 0, fields: [
            .bigInt(.int(0)),                                  // 1
            .bytes(.byteString(ByteString(bytes: Data())))     // 1
        ]))
        // 4 + 1 + 1 == 6
        #expect(pd.exMem() == 6)
    }

    @Test("empty array costs 4 (just the node)")
    func array_empty() {
        #expect(PlutusData.array([]).exMem() == 4)
    }

    @Test("array cost is 4 plus the sum of element costs")
    func array_withElements() {
        let pd = PlutusData.array([.bigInt(.int(1)), .bigInt(.int(2))])
        // 4 + 1 + 1 == 6
        #expect(pd.exMem() == 6)
    }

    @Test("indefiniteArray costs the same as a definite array")
    func indefiniteArray() {
        let pd = PlutusData.indefiniteArray(IndefiniteList([.bigInt(.int(1)), .bigInt(.int(2))]))
        #expect(pd.exMem() == 6)
    }

    @Test("empty map costs 4 (just the node)")
    func map_empty() {
        #expect(PlutusData.map([:]).exMem() == 4)
    }

    @Test("map cost is 4 plus the sum of key and value costs")
    func map_withEntries() {
        var dict = OrderedDictionary<PlutusData, PlutusData>()
        dict[.bytes(.byteString(ByteString(bytes: Data())))] = .bigInt(.int(0))  // 1 + 1
        let pd = PlutusData.map(dict)
        // 4 + (1 + 1) == 6
        #expect(pd.exMem() == 6)
    }

    @Test("bigInt delegates to the BigInteger cost")
    func bigInt_delegates() {
        #expect(PlutusData.bigInt(.int(0)).exMem() == 1)
    }

    @Test("empty bytes costs 1")
    func bytes_empty() {
        #expect(PlutusData.bytes(.byteString(ByteString(bytes: Data()))).exMem() == 1)
    }

    @Test("bytes cost grows by 8-byte words")
    func bytes_words() {
        #expect(PlutusData.bytes(.byteString(ByteString(bytes: Data(repeating: 0, count: 8)))).exMem() == 1)
        #expect(PlutusData.bytes(.byteString(ByteString(bytes: Data(repeating: 0, count: 9)))).exMem() == 2)
    }

    @Test("nested data structures accumulate node and leaf costs")
    func nested() {
        // array [ constr(0, [bigInt 0]) ]
        // outer array: 4 + (constr: 4 + bigInt: 1) == 4 + 5 == 9
        let pd = PlutusData.array([.constructor(Constr(tag: 0, fields: [.bigInt(.int(0))]))])
        #expect(pd.exMem() == 9)
    }
}

// MARK: — BigInteger.exMem()

@Suite("BigInteger — exMem memory cost")
struct BigIntegerExMemTests {

    @Test("int zero costs 1")
    func int_zero() {
        #expect(BigInteger.int(0).exMem() == 1)
    }

    @Test("non-zero small int costs 1")
    func int_nonZero() {
        #expect(BigInteger.int(123).exMem() == 1)
        #expect(BigInteger.int(-123).exMem() == 1)
    }

    @Test("bigUInt zero costs 1")
    func bigUInt_zero() {
        #expect(BigInteger.bigUInt(BigUInt(0)).exMem() == 1)
    }

    @Test("bigUInt fitting in one word costs 1")
    func bigUInt_oneWord() {
        #expect(BigInteger.bigUInt(BigUInt(1)).exMem() == 1)
    }

    @Test("bigUInt needing a second word costs 2")
    func bigUInt_twoWords() {
        #expect(BigInteger.bigUInt(BigUInt(1) << 64).exMem() == 2)
    }

    @Test("bigNInt zero costs 1")
    func bigNInt_zero() {
        #expect(BigInteger.bigNInt(BigInt(0)).exMem() == 1)
    }

    @Test("bigNInt measures magnitude in 64-bit words")
    func bigNInt_words() {
        #expect(BigInteger.bigNInt(BigInt(-1)).exMem() == 1)
        #expect(BigInteger.bigNInt(-(BigInt(1) << 64)).exMem() == 2)
    }
}
