import BigInt
import Foundation
import SwiftCardanoCore
import Testing

@testable import SwiftCardanoUPLC

/// Builtin inputs at the edges the conformance suite does not reach.
@Suite("Builtin edge cases")
struct BuiltinEdgeCaseTests {

    private func apply(_ function: DefaultFunction, _ args: [SwiftCardanoUPLC.Value]) throws -> SwiftCardanoUPLC.Value {
        var logs: [String] = []
        return try BuiltinRuntime.apply(function, to: args, costModel: .placeholder(), logs: &logs)
    }

    @Test("mapData keeps every pair, repeated keys included, in order")
    func mapDataKeepsRepeatedKeys() throws {
        let one = PlutusData.bigInt(.int(1))
        let (a, b) = (PlutusData.bigInt(.int(10)), PlutusData.bigInt(.int(20)))
        let pairs: [UPLCConstant] = [
            .pair(.data, .data, .data(one), .data(a)),
            .pair(.data, .data, .data(one), .data(b)),
        ]
        let result = try apply(.mapData, [.con(.list(.pair(.data, .data), pairs))])
        guard case .con(.data(.map(let map))) = result else {
            Issue.record("unexpected result \(result)")
            return
        }
        #expect(map.count == 2)
        #expect(map.map { $0.value } == [a, b])
    }

    @Test("writeBits fails, without trapping, on an index beyond Int's range")
    func writeBitsHugeIndex() throws {
        let huge = BigInt(1) << 70
        for index in [huge, -huge] {
            #expect(throws: MachineError.evaluationFailure) {
                try apply(.writeBits, [
                    .con(.byteString(Data([0]))),
                    .con(.list(.integer, [.integer(index)])),
                    .con(.bool(true)),
                ])
            }
        }
    }
}
