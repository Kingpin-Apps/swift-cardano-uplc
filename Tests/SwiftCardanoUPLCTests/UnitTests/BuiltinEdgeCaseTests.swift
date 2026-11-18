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

    // MARK: verifySchnorrSecp256k1Signature (BIP-340 test vectors)

    private func hex(_ string: String) -> Data {
        var bytes: [UInt8] = []
        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            bytes.append(UInt8(string[index..<next], radix: 16)!)
            index = next
        }
        return Data(bytes)
    }

    private func schnorr(key: String, message: String, signature: String) throws -> SwiftCardanoUPLC.Value {
        try apply(.verifySchnorrSecp256k1Signature, [
            .con(.byteString(hex(key))),
            .con(.byteString(hex(message))),
            .con(.byteString(hex(signature))),
        ])
    }

    private func isBool(_ value: SwiftCardanoUPLC.Value, _ expected: Bool) -> Bool {
        if case .con(.bool(let b)) = value { return b == expected }
        return false
    }

    private let bip340Key = "F9308A019258C31049344F85F89D5229B531C845836F99B08601F113BCE036F9"
    private let bip340Message = String(repeating: "00", count: 32)
    private let bip340Signature =
        "E907831F80848D1069A5371B402410364BDF1C5F8307B0084C55F1CE2DCA8215"
        + "25F66A4A85EA8B71E482A74F382D2CE5EBEEE8FDB2172F477DF4900D310536C0"

    @Test("verifySchnorrSecp256k1Signature accepts a valid BIP-340 signature")
    func schnorrValid() throws {
        let result = try schnorr(key: bip340Key, message: bip340Message, signature: bip340Signature)
        #expect(isBool(result, true))
    }

    @Test("verifySchnorrSecp256k1Signature accepts an empty message")
    func schnorrEmptyMessage() throws {
        let result = try schnorr(
            key: "778CAA53B4393AC467774D09497A87224BF9FAB6F6E68B23086497324D6FD117",
            message: "",
            signature: "71535DB165ECD9FBBC046E5FFAEA61186BB6AD436732FCCC25291A55895464CF"
                + "6069CE26BF03466228F19A3A62DB8A649F2D560FAC652827D1AF0574E427AB63"
        )
        #expect(isBool(result, true))
    }

    @Test("verifySchnorrSecp256k1Signature returns False for a different message")
    func schnorrWrongMessage() throws {
        let result = try schnorr(
            key: bip340Key, message: String(repeating: "00", count: 31) + "01", signature: bip340Signature)
        #expect(isBool(result, false))
    }

    @Test("verifySchnorrSecp256k1Signature fails on a key that is not a curve point")
    func schnorrOffCurveKey() throws {
        #expect(throws: MachineError.self) {
            try schnorr(
                key: "EEFDEA4CDB677750A420FEE807EACF21EB9898AE79B9768766E4FAA04A2D4A34",
                message: bip340Message, signature: bip340Signature)
        }
    }
}
