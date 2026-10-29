import Foundation
import OrderedCollections
import SwiftCardanoCore
import Testing

@testable import SwiftCardanoUPLC

/// A datum written with an indefinite-length map decodes to
/// `PlutusData.indefiniteMap`, which keeps its encoding. The builtins treat it
/// as the same value as a definite map; only its bytes differ.
@Suite("An indefinite map is a map to the builtins")
struct IndefiniteMapDataTests {

    /// `Constr 0 [Map [(I 1, I 2)]]` with an indefinite-length map.
    private let datum = "d8799fbf0102ffff"

    private func decoded() throws -> (datum: PlutusData, map: PlutusData) {
        let datum = try PlutusData.fromCBOR(data: datum.hexStringToData)
        guard case .constructor(let constr) = datum, let map = constr.fields.first else {
            throw MachineError.typeError("not a constructor")
        }
        return (datum, map)
    }

    private func apply(_ function: DefaultFunction, _ args: [SwiftCardanoUPLC.Value]) throws -> SwiftCardanoUPLC.Value {
        var logs: [String] = []
        return try BuiltinRuntime.apply(function, to: args, costModel: .placeholder(), logs: &logs)
    }

    private let definite = PlutusData.map(OrderedDictionary(uniqueKeysWithValues: [
        (PlutusData.bigInt(.int(1)), PlutusData.bigInt(.int(2)))
    ]))

    @Test("It decodes to the indefinite case")
    func decodes() throws {
        guard case .indefiniteMap = try decoded().map else {
            Issue.record("expected .indefiniteMap")
            return
        }
    }

    @Test("unMapData returns its pairs")
    func unMapData() throws {
        let result = try apply(.unMapData, [.con(.data(try decoded().map))])
        guard case .con(.list(_, let pairs)) = result, pairs.count == 1,
              case .pair(_, _, .data(let key), .data(let value)) = pairs[0] else {
            Issue.record("unexpected result \(result)")
            return
        }
        #expect(key == .bigInt(.int(1)))
        #expect(value == .bigInt(.int(2)))
    }

    @Test("chooseData takes the map branch")
    func chooseData() throws {
        let branches: [SwiftCardanoUPLC.Value] = (0..<5).map { .con(.integer(.init($0))) }
        let result = try apply(.chooseData, [.con(.data(try decoded().map))] + branches)
        guard case .con(.integer(let chosen)) = result else {
            Issue.record("unexpected result \(result)")
            return
        }
        #expect(chosen == 1)
    }

    @Test("equalsData and the memory cost match a definite map")
    func equalsDefinite() throws {
        let map = try decoded().map
        guard case .con(.bool(let equal)) = try apply(.equalsData, [.con(.data(map)), .con(.data(definite))]) else {
            Issue.record("equalsData did not return a boolean")
            return
        }
        #expect(equal)
        #expect(map.exMem() == definite.exMem())
        #expect(ExMemory.size(data: map) == ExMemory.size(data: definite))
    }

    @Test("serialiseData writes the map definite, as the ledger does")
    func serialiseData() throws {
        let result = try apply(.serialiseData, [.con(.data(try decoded().datum))])
        guard case .con(.byteString(let bytes)) = result else {
            Issue.record("unexpected result \(result)")
            return
        }
        #expect(bytes == "d8799fa10102ff".hexStringToData)
    }

    @Test("It prints as a map")
    func prints() throws {
        #expect(PrettyPrinter().printPlutusData(try decoded().map) == "Map [(I 1, I 2)]")
    }
}
