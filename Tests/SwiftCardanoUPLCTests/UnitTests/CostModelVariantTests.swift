@preconcurrency import BigInt
import Foundation
import SwiftCardanoCore
import Testing

@testable import SwiftCardanoUPLC

/// Plutus prices a handful of builtins differently depending on the language
/// *and* the protocol version — what it calls a builtin semantics variant.
///
/// The conformance corpus only pins PlutusV3, so nothing here was caught by it.
/// What caught it was a mainnet withdrawal script coming out a flat 4,152 steps
/// over: V1 and V2 were still being priced by variant A, which charges
/// `multiplyInteger` by the *sum* of its argument sizes where every chain since
/// Chang charges by their *product*.
@Suite("Builtin semantics variants")
struct CostModelVariantTests {

    /// The mainnet parameters the fixtures were taken under.
    static func table(for version: PlutusVersion) throws -> [String: Int64] {
        let url = try #require(Bundle.module.url(
            forResource: "Resources/mainnet/protocol-parameters", withExtension: "json"
        ))
        let params = try JSONDecoder().decode(
            ProtocolParameters.self, from: try Data(contentsOf: url)
        )
        let names: [String]
        let languageId: Int
        switch version {
            case .v1: names = CostModelParameterNames.plutusv1; languageId = 1
            case .v2: names = CostModelParameterNames.plutusv2; languageId = 2
            case .v3: names = CostModelParameterNames.plutusv3; languageId = 3
        }
        let values = try #require(params.costModels.getVersion(languageId))
        return Dictionary(uniqueKeysWithValues: zip(names, values))
    }

    /// Two one-word integers: their sizes sum to two and multiply to one, so the
    /// two formulas differ by exactly one slope.
    private static let oneWordArguments: [SwiftCardanoUPLC.Value] = [
        .con(.integer(BigInt(1))), .con(.integer(BigInt(1))),
    ]

    @Test("multiplyInteger is priced by the product of sizes from Chang onwards", arguments: [
        PlutusVersion.v1, .v2,
    ])
    func multiplyIntegerVariant(version: PlutusVersion) throws {
        let table = try Self.table(for: version)
        let slope = try #require(table["multiplyInteger-cpu-arguments-slope"])
        let intercept = try #require(table["multiplyInteger-cpu-arguments-intercept"])

        let beforeChang = try CostModel.fromParameters(
            table, version: version, protocolMajorVersion: 8
        )
        let sinceChang = try CostModel.fromParameters(
            table, version: version, protocolMajorVersion: 9
        )
        let before = try #require(
            beforeChang.budget(for: .multiplyInteger, arguments: Self.oneWordArguments)
        )
        let since = try #require(
            sinceChang.budget(for: .multiplyInteger, arguments: Self.oneWordArguments)
        )

        #expect(before.cpu == intercept + slope * 2, "variant A sums the sizes")
        #expect(since.cpu == intercept + slope * 1, "variant B multiplies them")
        #expect(before.cpu - since.cpu == slope)
        // Memory is unaffected: it sums the sizes in both.
        #expect(before.mem == since.mem)
    }

    @Test("V3 has always priced multiplyInteger by the product")
    func v3IsAlwaysVariantC() throws {
        let table = try Self.table(for: .v3)
        let intercept = try #require(table["multiplyInteger-cpu-arguments-intercept"])
        let slope = try #require(table["multiplyInteger-cpu-arguments-slope"])
        for protocolVersion in [9, 10, 11] {
            let model = try CostModel.fromParameters(
                table, version: .v3, protocolMajorVersion: protocolVersion
            )
            let budget = try #require(
                model.budget(for: .multiplyInteger, arguments: Self.oneWordArguments)
            )
            #expect(budget.cpu == intercept + slope, "at protocol version \(protocolVersion)")
        }
    }

    /// The other change Chang brought to V1 and V2: the signature check is priced
    /// by the size of the *message* rather than the size of the signature.
    @Test("verifyEd25519Signature is priced by the message from Chang onwards")
    func verifyEd25519Variant() throws {
        let table = try Self.table(for: .v2)
        let slope = try #require(table["verifyEd25519Signature-cpu-arguments-slope"])
        // A long message and a short signature, so the two differ.
        let arguments: [SwiftCardanoUPLC.Value] = [
            .con(.byteString(Data(repeating: 0, count: 32))),
            .con(.byteString(Data(repeating: 0, count: 800))),
            .con(.byteString(Data(repeating: 0, count: 64))),
        ]
        let messageWords = Int64(100)   // 800 bytes in eight-byte words
        let signatureWords = Int64(8)   // 64 bytes

        let beforeChang = try #require(
            try CostModel.fromParameters(table, version: .v2, protocolMajorVersion: 8)
                .budget(for: .verifyEd25519Signature, arguments: arguments)
        )
        let sinceChang = try #require(
            try CostModel.fromParameters(table, version: .v2, protocolMajorVersion: 9)
                .budget(for: .verifyEd25519Signature, arguments: arguments)
        )
        #expect(sinceChang.cpu - beforeChang.cpu == slope * (messageWords - signatureWords))
    }
}
