import Testing
import Foundation
import SwiftCardanoCore
@testable import SwiftCardanoUPLC

// MARK: — Tests

@Suite("PhaseTwo — Unresolvable Spend Input Handling")
struct PhaseTwoUnresolvableInputTests {

    // MARK: — Core behaviour: evaluate does not throw

    @Test("Unresolvable spend input does not throw — returns failed result instead")
    func unresolvableSpendInput_doesNotThrow() async throws {
        let tx = makeTransaction(spendRedeemerCount: 1)
        let result = try await PhaseTwo(costModel: .placeholder())
            .evaluate(transaction: tx, resolvedInputs: [])

        #expect(result.redeemers.count == 1)
        #expect(!result.success)
    }

    // MARK: — Error shape: clearly an input-resolution warning, not a script failure

    @Test("Unresolvable spend input error message identifies the missing input")
    func unresolvableSpendInput_errorMessageContainsUnresolvedSpentInput() async throws {
        let tx = makeTransaction(spendRedeemerCount: 1)
        let result = try await PhaseTwo(costModel: .placeholder())
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
        let result = try await PhaseTwo(costModel: .placeholder())
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
        let result = try await PhaseTwo(costModel: .placeholder())
            .evaluate(transaction: tx, resolvedInputs: [])

        let r = try #require(result.redeemers.first)
        #expect(!r.passed)
    }

    @Test("Unresolvable spend input result carries the correct redeemer array index")
    func unresolvableSpendInput_hasCorrectIndex() async throws {
        let tx = makeTransaction(spendRedeemerCount: 1)
        let result = try await PhaseTwo(costModel: .placeholder())
            .evaluate(transaction: tx, resolvedInputs: [])

        let r = try #require(result.redeemers.first)
        #expect(r.index == 0)
    }

    @Test("PhaseTwoResult.success is false when any spend input is unresolvable")
    func phaseTwoResult_successIsFalse_whenInputUnresolvable() async throws {
        let tx = makeTransaction(spendRedeemerCount: 1)
        let result = try await PhaseTwo(costModel: .placeholder())
            .evaluate(transaction: tx, resolvedInputs: [])

        #expect(!result.success)
    }

    // MARK: — Multiple redeemers

    @Test("All unresolvable spend redeemers each get their own failed result")
    func multipleUnresolvableInputs_allGetFailedResults() async throws {
        let tx = makeTransaction(spendRedeemerCount: 3)
        let result = try await PhaseTwo(costModel: .placeholder())
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
        let result = try await PhaseTwo(costModel: .placeholder())
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

// MARK: — Protocol parameters fixture

private func unit(_ numerator: UInt64, _ denominator: UInt64) -> UnitInterval {
    UnitInterval(numerator: numerator, denominator: denominator)
}

private func dummyProtocolParameters() -> ProtocolParameters {
    ProtocolParameters(
        collateralPercentage: 150,
        committeeMaxTermLength: 200,
        committeeMinSize: 7,
        costModels: ProtocolParametersCostModels(PlutusV1: [], PlutusV2: [], PlutusV3: []),
        dRepActivity: 20,
        dRepDeposit: 500_000_000,
        dRepVotingThresholds: DRepVotingThresholds(
            committeeNoConfidence: unit(3, 5), committeeNormal: unit(13, 20),
            hardForkInitiation: unit(3, 5), motionNoConfidence: unit(3, 5),
            ppEconomicGroup: unit(67, 100), ppGovGroup: unit(3, 4),
            ppNetworkGroup: unit(67, 100), ppTechnicalGroup: unit(67, 100),
            treasuryWithdrawal: unit(67, 100), updateToConstitution: unit(3, 4)
        ),
        executionUnitPrices: ExecutionUnitPrices(
            priceMemory: NonNegativeInterval(numerator: 577, denominator: 10_000),
            priceSteps: NonNegativeInterval(numerator: 721, denominator: 10_000_000)),
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
        monetaryExpansion: unit(3, 1000),
        poolPledgeInfluence: NonNegativeInterval(numerator: 3, denominator: 10),
        poolRetireMaxEpoch: 18,
        poolVotingThresholds: ProtocolParametersPoolVotingThresholds(
            committeeNoConfidence: unit(3, 5), committeeNormal: unit(13, 20),
            hardForkInitiation: unit(51, 100), motionNoConfidence: unit(3, 5),
            ppSecurityGroup: unit(3, 4)
        ),
        protocolVersion: ProtocolParametersProtocolVersion(major: 9, minor: 0),
        stakeAddressDeposit: 2_000_000,
        stakePoolDeposit: 500_000_000,
        stakePoolTargetNum: 500,
        treasuryCut: unit(1, 5),
        txFeeFixed: 155381,
        txFeePerByte: 44,
        utxoCostPerByte: 4310
    )
}
