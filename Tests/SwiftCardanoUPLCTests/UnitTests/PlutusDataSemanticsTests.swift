import Testing
import BigInt
import Foundation
import SwiftCardanoCore
@testable import SwiftCardanoUPLC

/// `PlutusData` carries representation detail with no on-chain meaning, and
/// Swift's synthesised `==` compares all of it. A datum decoded from the chain
/// and the same value rebuilt by a script land on different representations,
/// so `equalsData` reported them unequal and correct validators rejected good
/// transactions.
@Suite("Plutus Data equality ignores representation")
struct PlutusDataSemanticsTests {

    private func bytes(_ data: Data) -> PlutusData { .bytes(.byteString(ByteString(bytes: data))) }
    private func bounded(_ data: Data) throws -> PlutusData { .bytes(.boundedBytes(try BoundedBytes(bytes: data))) }

    @Test("the two byte-string representations compare equal")
    func byteRepresentations() throws {
        let payload = Data(repeating: 0xAB, count: 28)
        let a = bytes(payload)
        let b = try bounded(payload)
        #expect(a != b, "precondition: the synthesised == distinguishes these")
        #expect(PlutusDataSemantics.equal(a, b))
    }

    @Test("the integer representations compare equal")
    func integerRepresentations() {
        let a = PlutusData.bigInt(.int(5))
        let b = PlutusData.bigInt(.bigUInt(BigUInt(5)))
        #expect(PlutusDataSemantics.equal(a, b))
        #expect(!PlutusDataSemantics.equal(a, .bigInt(.int(6))))
    }

    @Test("negative integers compare across representations")
    func negativeIntegers() {
        #expect(PlutusDataSemantics.equal(.bigInt(.int(-7)), .bigInt(.bigNInt(BigInt(7)))))
    }

    @Test("definite and indefinite lists compare equal")
    func listRepresentations() {
        let items: [PlutusData] = [.bigInt(.int(1)), .bigInt(.int(2))]
        let a = PlutusData.array(items)
        let b = PlutusData.indefiniteArray(IndefiniteList(items))
        #expect(a != b, "precondition: the synthesised == distinguishes these")
        #expect(PlutusDataSemantics.equal(a, b))
    }

    @Test("a constructor's field-encoding flag does not affect equality")
    func constructorEncodingFlag() {
        let field = PlutusData.bigInt(.int(1))
        let a = PlutusData.constructor(Constr(tag: 1, fields: [field], useIndefiniteList: true))
        let b = PlutusData.constructor(Constr(tag: 1, fields: [field], useIndefiniteList: false))
        #expect(PlutusDataSemantics.equal(a, b))
    }

    @Test("different tags, fields and lengths are still unequal")
    func genuineDifferences() {
        let one = PlutusData.bigInt(.int(1))
        #expect(!PlutusDataSemantics.equal(
            .constructor(Constr(tag: 0, fields: [one])),
            .constructor(Constr(tag: 1, fields: [one]))))
        #expect(!PlutusDataSemantics.equal(.array([one]), .array([one, one])))
        #expect(!PlutusDataSemantics.equal(.array([one]), .bigInt(.int(1))))
    }

    @Test("map order is part of the value")
    func mapOrderMatters() {
        let a = PlutusData.map([.bigInt(.int(1)): .bigInt(.int(2)), .bigInt(.int(3)): .bigInt(.int(4))])
        let b = PlutusData.map([.bigInt(.int(3)): .bigInt(.int(4)), .bigInt(.int(1)): .bigInt(.int(2))])
        #expect(!PlutusDataSemantics.equal(a, b))
        #expect(PlutusDataSemantics.equal(a, a))
    }

    @Test("nested differences in representation still compare equal")
    func nested() throws {
        let payload = Data(repeating: 0x01, count: 4)
        let a = PlutusData.constructor(Constr(tag: 0, fields: [.array([bytes(payload)])]))
        let b = PlutusData.constructor(Constr(tag: 0, fields: [
            .indefiniteArray(IndefiniteList([try bounded(payload)]))
        ]))
        #expect(PlutusDataSemantics.equal(a, b))
    }
}
