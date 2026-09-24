@preconcurrency import BigInt
import Foundation
import OrderedCollections
import SwiftCardanoCore
import Testing

@testable import SwiftCardanoUPLC

/// `equalsData` compares two `Data` values the way the ledger does: by
/// structure and content, ignoring how each part happens to be represented.
///
/// This is not hypothetical. A datum decoded from the chain and the same value
/// rebuilt by a script take different representations — a byte string as
/// `.boundedBytes` or `.byteString`, a list as `.array` or `.indefiniteArray` —
/// and comparing that detail made `equalsData` return false for two values with
/// byte-identical CBOR, which made correct validators reject good transactions.
/// The comparison itself lives in ``SwiftCardanoCore``; these tests pin the
/// builtin's behaviour.
@Suite("equalsData compares values, not representations")
struct PlutusDataSemanticsTests {

    private func equalsData(_ lhs: PlutusData, _ rhs: PlutusData) throws -> Bool {
        var logs: [String] = []
        let result = try BuiltinRuntime.apply(
            .equalsData,
            to: [.con(.data(lhs)), .con(.data(rhs))],
            costModel: .placeholder(),
            logs: &logs
        )
        guard case .con(.bool(let equal)) = result else {
            throw MachineError.typeError("equalsData did not return a boolean")
        }
        return equal
    }

    @Test("The two byte-string representations compare equal")
    func byteStrings() throws {
        let raw = Data(repeating: 0x11, count: 8)
        #expect(try equalsData(
            .bytes(.boundedBytes(try BoundedBytes(bytes: raw))),
            .bytes(.byteString(ByteString(bytes: raw)))
        ))
        #expect(try !equalsData(
            .bytes(try Bytes(from: Data([0x01]))),
            .bytes(try Bytes(from: Data([0x02])))
        ))
    }

    @Test("Integers compare by value across the small and big cases")
    func integers() throws {
        #expect(try equalsData(.bigInt(.int(5)), .bigInt(.bigUInt(BigUInt(5)))))
        #expect(try !equalsData(.bigInt(.int(5)), .bigInt(.int(6))))
        #expect(try equalsData(.bigInt(.int(-7)), .bigInt(.bigNInt(BigInt(-7)))))
    }

    @Test("Definite and indefinite lists compare equal")
    func lists() throws {
        let elements: [PlutusData] = [.bigInt(.int(1)), .bigInt(.int(2))]
        #expect(try equalsData(.array(elements), .indefiniteArray(IndefiniteList(elements))))
        #expect(try !equalsData(.array(elements), .array([elements[0]])))
    }

    @Test("A constructor ignores how its fields were encoded")
    func constructors() throws {
        let fields: [PlutusData] = [.bytes(try Bytes(from: Data([0xAB])))]
        #expect(try equalsData(
            .constructor(Constr(tag: 1, fields: fields, useIndefiniteList: true)),
            .constructor(Constr(tag: 1, fields: fields, useIndefiniteList: false))
        ))
        #expect(try !equalsData(
            .constructor(Constr(tag: 1, fields: fields)),
            .constructor(Constr(tag: 2, fields: fields))
        ))
    }

    @Test("A map keeps its order, because a Plutus map is a list of pairs")
    func maps() throws {
        let forwards = PlutusData.map(OrderedDictionary(uniqueKeysWithValues: [
            (PlutusData.bigInt(.int(1)), PlutusData.bigInt(.int(10))),
            (PlutusData.bigInt(.int(2)), PlutusData.bigInt(.int(20))),
        ]))
        let sameHeldDifferently = PlutusData.map(OrderedDictionary(uniqueKeysWithValues: [
            (PlutusData.bigInt(.bigUInt(BigUInt(1))), PlutusData.bigInt(.int(10))),
            (PlutusData.bigInt(.int(2)), PlutusData.bigInt(.bigUInt(BigUInt(20)))),
        ]))
        let backwards = PlutusData.map(OrderedDictionary(uniqueKeysWithValues: [
            (PlutusData.bigInt(.int(2)), PlutusData.bigInt(.int(20))),
            (PlutusData.bigInt(.int(1)), PlutusData.bigInt(.int(10))),
        ]))
        #expect(try equalsData(forwards, sameHeldDifferently))
        #expect(try !equalsData(forwards, backwards))
    }

    @Test("Values of different shapes stay unequal")
    func shapes() throws {
        let integer = PlutusData.bigInt(.int(0))
        #expect(try !equalsData(.bytes(try Bytes(from: Data([0x00]))), integer))
        #expect(try !equalsData(.array([integer]), .constructor(Constr(tag: 0, fields: [integer]))))
    }
}
