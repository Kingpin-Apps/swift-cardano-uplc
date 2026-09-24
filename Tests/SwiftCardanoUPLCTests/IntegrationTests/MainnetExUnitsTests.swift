import Foundation
import SwiftCardanoCore
import Testing

@testable import SwiftCardanoUPLC

/// Runs real mainnet transactions and checks the execution units against the ones
/// they declare on chain.
///
/// This is the other half of the story told by `LedgerScriptContextTests`. That
/// suite proves the *context* is byte-exact; this one proves the machine and the
/// cost model turn it into the same budget the chain charged. A transaction that
/// was accepted by the ledger declares the units its scripts really used, so any
/// difference here is a bug in this library.
///
/// Both transactions carry a validity interval, which is what most real
/// transactions have and what this library refused to evaluate until it could
/// convert slots to POSIX time.
///
/// `Resources/mainnet/README.md` records how to add another one.
@Suite("Mainnet execution units")
struct MainnetExUnitsTests {

    struct Declared: Codable {
        let purpose: String
        let memory: UInt64
        let steps: UInt64
    }

    struct Fixture: Codable {
        /// The transaction's hash, which is also its name.
        let name: String
        let transaction: String
        /// Every input the transaction references, reference inputs included.
        let resolvedInputs: [String]
        let invalidBefore: String?
        let invalidAfter: String?
        let declared: [Declared]
    }

    static let resources = Bundle.module.url(forResource: "Resources/mainnet", withExtension: nil)

    static let fixtures: [Fixture] = {
        guard let url = resources?.appendingPathComponent("transactions.json"),
              let data = try? Data(contentsOf: url),
              let fixtures = try? JSONDecoder().decode([Fixture].self, from: data)
        else { return [] }
        return fixtures.sorted { $0.name < $1.name }
    }()

    static func protocolParameters() throws -> ProtocolParameters {
        let url = try #require(resources?.appendingPathComponent("protocol-parameters.json"))
        return try JSONDecoder().decode(ProtocolParameters.self, from: try Data(contentsOf: url))
    }

    @Test("Every fixture was loaded")
    func fixturesArePresent() {
        #expect(!Self.fixtures.isEmpty, "no mainnet transactions were found in the bundle")
    }

    @Test("The units come out as the chain charged them", arguments: Self.fixtures)
    func unitsMatchTheChain(fixture: Fixture) async throws {
        let transaction = try Transaction.fromCBORHex(fixture.transaction)
        let resolvedInputs = try fixture.resolvedInputs.map { try UTxO.fromCBORHex($0) }
        let phaseTwo = try PhaseTwo(
            protocolParameters: try Self.protocolParameters(), slotTimeline: .mainnet
        )

        let result = try await phaseTwo.evaluate(
            transaction: transaction, resolvedInputs: resolvedInputs
        )
        #expect(result.redeemers.count == fixture.declared.count)

        for evaluated in result.redeemers {
            guard fixture.declared.indices.contains(evaluated.index) else { continue }
            let declared = fixture.declared[evaluated.index]
            let label = "\(fixture.name.prefix(16)) redeemer \(evaluated.index) (\(declared.purpose))"

            #expect(evaluated.passed, "\(label) failed: \(String(describing: evaluated.error))")
            #expect(evaluated.budgetMeasured, "\(label) ran without a real cost model")
            guard evaluated.budgetMeasured else { continue }

            let steps = ExBudget.restricted.cpu - evaluated.remainingBudget.cpu
            let memory = ExBudget.restricted.mem - evaluated.remainingBudget.mem
            #expect(steps == declared.steps, "\(label): cpu")
            #expect(memory == declared.memory, "\(label): memory")
        }
    }
}

extension MainnetExUnitsTests.Fixture: CustomTestStringConvertible {
    var testDescription: String { String(name.prefix(16)) }
}
