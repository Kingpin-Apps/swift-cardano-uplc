import Foundation
import SwiftCardanoCore
import Testing

@testable import SwiftCardanoUPLC

/// Checks the script context against the ledger's own, byte for byte.
///
/// Each fixture was produced by `cardano-cli conway transaction
/// calculate-plutus-script-cost offline` against a synced mainnet node. When a
/// script fails, the ledger reports the arguments it handed it — base64-encoded
/// CBOR — so a validator that simply returns `False` makes the node print the
/// context it built. That is what `expectedContext` holds.
///
/// Matching execution units is a much weaker check: the budget only reflects
/// the parts of the context a script actually looks at, so a field in the wrong
/// order or missing entirely costs nothing and goes unnoticed. Comparing the
/// serialised context leaves nowhere for a mistake to hide.
///
/// `Resources/ledgercontext/README.md` records how to regenerate a fixture.
@Suite("Script context against the ledger")
struct LedgerScriptContextTests {

    struct Fixture: Codable {
        let name: String
        let note: String
        let transaction: String
        let resolvedInputs: [String]
        let redeemerTag: String
        let redeemerIndex: Int
        let protocolMajorVersion: Int
        /// Which language's context this is. V1 and V2 see a different structure
        /// from V3, not a smaller one.
        let plutusVersion: String
        let expectedContext: String
    }

    static let fixtures: [Fixture] = {
        guard let directory = Bundle.module.url(
            forResource: "Resources/ledgercontext", withExtension: nil
        ) else {
            return []
        }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(Fixture.self, from: data)
            }
            .sorted { $0.name < $1.name }
    }()

    @Test("Every fixture was loaded")
    func fixturesArePresent() {
        #expect(!Self.fixtures.isEmpty, "no ledger context fixtures were found in the bundle")
    }

    @Test("The context matches the ledger's, byte for byte", arguments: Self.fixtures)
    func contextMatchesLedger(fixture: Fixture) throws {
        let transaction = try Transaction.fromCBORHex(fixture.transaction)
        let resolvedInputs = try fixture.resolvedInputs.map { try UTxO.fromCBORHex($0) }
        let redeemer = try redeemer(in: transaction, fixture: fixture)

        let context = try buildScriptContext(
            for: redeemer,
            transaction: transaction,
            resolvedInputs: resolvedInputs,
            version: try fixture.version,
            protocolMajorVersion: fixture.protocolMajorVersion,
            // The fixtures were generated against a mainnet node, so its slots
            // are the ones the ledger converted.
            slotTimeline: .mainnet
        )

        let built = try context.toCBORHex()
        guard built != fixture.expectedContext else { return }
        // A diff is far more use than "not equal" on 400 bytes of CBOR.
        Issue.record(
            """
            \(fixture.name): the context differs from the ledger's (\(fixture.note))
            first difference at byte \(firstDifference(built, fixture.expectedContext) ?? -1)
            ledger: \(fixture.expectedContext)
            built:  \(built)
            """
        )
    }

    /// The redeemer the fixture is about.
    private func redeemer(in transaction: Transaction, fixture: Fixture) throws -> Redeemer {
        let tags: [String: RedeemerTag] = [
            "spend": .spend, "mint": .mint, "cert": .cert,
            "reward": .reward, "voting": .voting, "proposing": .proposing,
        ]
        guard let tag = tags[fixture.redeemerTag] else {
            throw ScriptContextError.unsupportedFeature("unknown tag \(fixture.redeemerTag)")
        }
        guard let redeemers = transaction.transactionWitnessSet.redeemers else {
            throw ScriptContextError.unsupportedFeature("the fixture has no redeemers")
        }
        let all: [Redeemer]
        switch redeemers {
        case .list(let list): all = list.compactMap { $0 as? Redeemer }
        case .map(let map):
            all = map.pairs.map {
                Redeemer(tag: $0.key.tag, index: $0.key.index, data: $0.value.data,
                         exUnits: $0.value.exUnits)
            }
        }
        guard let found = all.first(where: { $0.tag == tag && $0.index == fixture.redeemerIndex })
        else {
            throw ScriptContextError.unsupportedFeature(
                "the fixture names \(fixture.redeemerTag)[\(fixture.redeemerIndex)], "
                + "which the transaction does not carry"
            )
        }
        return found
    }

    /// The byte offset the two hex strings first disagree at.
    private func firstDifference(_ lhs: String, _ rhs: String) -> Int? {
        for (index, pair) in zip(Array(lhs), Array(rhs)).enumerated() where pair.0 != pair.1 {
            return index / 2
        }
        return lhs.count == rhs.count ? nil : min(lhs.count, rhs.count) / 2
    }
}

extension LedgerScriptContextTests.Fixture {
    var version: PlutusVersion {
        get throws {
            switch plutusVersion {
                case "v1": return .v1
                case "v2": return .v2
                case "v3": return .v3
                default:
                    throw ScriptContextError.unsupportedVersion(plutusVersion)
            }
        }
    }
}

extension LedgerScriptContextTests.Fixture: CustomTestStringConvertible {
    var testDescription: String { name }
}
