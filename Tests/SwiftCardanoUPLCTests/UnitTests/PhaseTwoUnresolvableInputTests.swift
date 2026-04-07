import Testing
import Foundation
import SwiftCardanoCore
import SwiftCardanoChain
@testable import SwiftCardanoUPLC

// MARK: — Tests

@Suite("PhaseTwo — Unresolvable Spend Input Handling")
struct PhaseTwoUnresolvableInputTests {

    // MARK: — Core behaviour: evaluate does not throw

    @Test("Unresolvable spend input does not throw — returns failed result instead")
    func unresolvableSpendInput_doesNotThrow() async throws {
        let tx = makeTransaction(spendRedeemerCount: 1)
        let result = try await PhaseTwo(chainContext: MockChainContext())
            .evaluate(transaction: tx, resolvedInputs: [])

        #expect(result.redeemers.count == 1)
        #expect(!result.success)
    }

    // MARK: — Error shape: clearly an input-resolution warning, not a script failure

    @Test("Unresolvable spend input error message identifies the missing input")
    func unresolvableSpendInput_errorMessageContainsUnresolvedSpentInput() async throws {
        let tx = makeTransaction(spendRedeemerCount: 1)
        let result = try await PhaseTwo(chainContext: MockChainContext())
            .evaluate(transaction: tx, resolvedInputs: [])

        let r = try #require(result.redeemers.first)
        guard case .typeError(let message) = r.error else {
            Issue.record("Expected MachineError.typeError, got \(String(describing: r.error))")
            return
        }
        #expect(message.contains("Unresolved spent input"),
                "Error message should signal unresolved input, got: \(message)")
    }

    @Test("Unresolvable spend input is NOT reported as a script evaluation failure")
    func unresolvableSpendInput_isNotEvaluationFailure() async throws {
        let tx = makeTransaction(spendRedeemerCount: 1)
        let result = try await PhaseTwo(chainContext: MockChainContext())
            .evaluate(transaction: tx, resolvedInputs: [])

        let r = try #require(result.redeemers.first)
        // .evaluationFailure means the script actually ran and errored — that must NOT be the case here
        #expect(r.error != .evaluationFailure,
                "Unresolved input should not be classified as a script evaluation failure")
    }

    // MARK: — Result metadata

    @Test("Unresolvable spend input result is marked as not passed")
    func unresolvableSpendInput_resultNotPassed() async throws {
        let tx = makeTransaction(spendRedeemerCount: 1)
        let result = try await PhaseTwo(chainContext: MockChainContext())
            .evaluate(transaction: tx, resolvedInputs: [])

        let r = try #require(result.redeemers.first)
        #expect(!r.passed)
    }

    @Test("Unresolvable spend input result carries the correct redeemer array index")
    func unresolvableSpendInput_hasCorrectIndex() async throws {
        let tx = makeTransaction(spendRedeemerCount: 1)
        let result = try await PhaseTwo(chainContext: MockChainContext())
            .evaluate(transaction: tx, resolvedInputs: [])

        let r = try #require(result.redeemers.first)
        #expect(r.index == 0)
    }

    @Test("PhaseTwoResult.success is false when any spend input is unresolvable")
    func phaseTwoResult_successIsFalse_whenInputUnresolvable() async throws {
        let tx = makeTransaction(spendRedeemerCount: 1)
        let result = try await PhaseTwo(chainContext: MockChainContext())
            .evaluate(transaction: tx, resolvedInputs: [])

        #expect(!result.success)
    }

    // MARK: — Multiple redeemers

    @Test("All unresolvable spend redeemers each get their own failed result")
    func multipleUnresolvableInputs_allGetFailedResults() async throws {
        let tx = makeTransaction(spendRedeemerCount: 3)
        let result = try await PhaseTwo(chainContext: MockChainContext())
            .evaluate(transaction: tx, resolvedInputs: [])

        #expect(result.redeemers.count == 3)
        #expect(!result.success)

        for r in result.redeemers {
            #expect(!r.passed, "Redeemer at index \(r.index) should not pass")
            guard case .typeError(let message) = r.error else {
                Issue.record("Expected typeError for redeemer \(r.index), got \(String(describing: r.error))")
                continue
            }
            #expect(message.contains("Unresolved spent input"),
                    "Error for redeemer \(r.index) should mention unresolved input, got: \(message)")
        }

        // Results are sorted by index
        let indices = result.redeemers.map(\.index)
        #expect(indices == indices.sorted())
    }

    @Test("Results are returned in ascending index order even with multiple unresolvable inputs")
    func unresolvableInputs_resultsAreSortedByIndex() async throws {
        let tx = makeTransaction(spendRedeemerCount: 2)
        let result = try await PhaseTwo(chainContext: MockChainContext())
            .evaluate(transaction: tx, resolvedInputs: [])

        #expect(result.redeemers.map(\.index) == [0, 1])
    }
}

// MARK: — Fixture builder

private func makeTransaction(spendRedeemerCount: Int) -> Transaction {
    // Use distinct tx IDs so the sort order matches insertion order (index 0 < index 1 etc.)
    let inputs: [TransactionInput] = (0..<spendRedeemerCount).map { i in
        let txId = TransactionId(payload: Data(repeating: UInt8(i + 1), count: 32))
        return TransactionInput(transactionId: txId, index: 0)
    }
    let body = TransactionBody(
        inputs: .list(inputs),
        outputs: [],
        fee: 0
    )
    let redeemers: [any RedeemerProtocol] = (0..<spendRedeemerCount).map { i in
        Redeemer(tag: .spend, index: i, data: .bigInt(.int(0)))
    }
    let witnesses = TransactionWitnessSet(redeemers: .list(redeemers))
    return Transaction(transactionBody: body, transactionWitnessSet: witnesses)
}

// MARK: — Mock chain context

/// Minimal ChainContext that satisfies `CostModel.fromChainContext` (the only call made
/// during Phase 2 evaluation). All other protocol requirements throw or return empty values.
private struct MockChainContext: ChainContext {
    var name: String { "mock" }
    var type: ContextType { .offline }
    var networkId: NetworkId { .testnet }

    var protocolParameters: () async throws -> ProtocolParameters {
        // fromProtocolParams ignores all values and returns .defaultV2() so any
        // ProtocolParameters instance is acceptable here.
        { Self.dummyProtocolParameters() }
    }

    var genesisParameters: () async throws -> GenesisParameters {
        { throw MockContextError.notImplemented }
    }

    var epoch: () async throws -> Int { { 0 } }
    var era: () async throws -> Era? { { nil } }
    var lastBlockSlot: () async throws -> Int { { 0 } }

    func utxos(address: Address) async throws -> [UTxO] { [] }
    func submitTxCBOR(cbor: Data) async throws -> String { throw MockContextError.notImplemented }
    func evaluateTxCBOR(cbor: Data) async throws -> [String: ExecutionUnits] { throw MockContextError.notImplemented }
    func stakeAddressInfo(address: Address) async throws -> [StakeAddressInfo] { [] }
    func stakePools() async throws -> [PoolOperator] { throw MockContextError.notImplemented }
    func kesPeriodInfo(pool: PoolOperator?, opCert: OperationalCertificate?) async throws -> KESPeriodInfo {
        throw MockContextError.notImplemented
    }
    func stakePoolInfo(poolId: String) async throws -> StakePoolInfo {
        throw MockContextError.notImplemented
    }

    private static func dummyProtocolParameters() -> ProtocolParameters {
        ProtocolParameters(
            collateralPercentage: 150,
            committeeMaxTermLength: 200,
            committeeMinSize: 7,
            costModels: ProtocolParametersCostModels(PlutusV1: [], PlutusV2: [], PlutusV3: []),
            dRepActivity: 20,
            dRepDeposit: 500_000_000,
            dRepVotingThresholds: DRepVotingThresholds(
                committeeNoConfidence: 0.6, committeeNormal: 0.65,
                hardForkInitiation: 0.6, motionNoConfidence: 0.6,
                ppEconomicGroup: 0.67, ppGovGroup: 0.75,
                ppNetworkGroup: 0.67, ppTechnicalGroup: 0.67,
                treasuryWithdrawal: 0.67, updateToConstitution: 0.75
            ),
            executionUnitPrices: ExecutionUnitPrices(priceMemory: 0.0577, priceSteps: 0.0000721),
            govActionDeposit: 100_000_000_000,
            govActionLifetime: 6,
            maxBlockBodySize: 90112,
            maxBlockExecutionUnits: ProtocolParametersExecutionUnits(memory: 62_000_000, steps: 20_000_000_000),
            maxBlockHeaderSize: 1100,
            maxCollateralInputs: 3,
            maxTxExecutionUnits: ProtocolParametersExecutionUnits(memory: 14_000_000, steps: 10_000_000_000),
            maxTxSize: 16384,
            maxValueSize: 5000,
            minPoolCost: 170_000_000,
            monetaryExpansion: 0.003,
            poolPledgeInfluence: 0.3,
            poolRetireMaxEpoch: 18,
            poolVotingThresholds: ProtocolParametersPoolVotingThresholds(
                committeeNoConfidence: 0.6, committeeNormal: 0.65,
                hardForkInitiation: 0.51, motionNoConfidence: 0.6,
                ppSecurityGroup: 0.75
            ),
            protocolVersion: ProtocolParametersProtocolVersion(major: 9, minor: 0),
            stakeAddressDeposit: 2_000_000,
            stakePoolDeposit: 500_000_000,
            stakePoolTargetNum: 500,
            treasuryCut: 0.2,
            txFeeFixed: 155381,
            txFeePerByte: 44,
            utxoCostPerByte: 4310
        )
    }
}

private enum MockContextError: Error {
    case notImplemented
}
