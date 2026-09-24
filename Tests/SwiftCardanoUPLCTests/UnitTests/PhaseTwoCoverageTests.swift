import Testing
import Foundation
import SwiftCardanoCore
@testable import SwiftCardanoUPLC

// MARK: — Fixtures

private func scriptAddr(_ byte: UInt8 = 0xAB) throws -> Address {
    try Address(
        paymentPart: .scriptHash(ScriptHash(payload: Data(repeating: byte, count: SCRIPT_HASH_SIZE))),
        stakingPart: nil,
        network: .testnet
    )
}

private func vkeyAddr(_ byte: UInt8 = 0x11) throws -> Address {
    try Address(
        paymentPart: .verificationKeyHash(VerificationKeyHash(payload: Data(repeating: byte, count: VERIFICATION_KEY_HASH_SIZE))),
        stakingPart: nil,
        network: .testnet
    )
}

private func input(_ idByte: UInt8 = 0x01, index: UInt16 = 0) -> TransactionInput {
    TransactionInput(
        transactionId: TransactionId(payload: Data(repeating: idByte, count: TRANSACTION_HASH_SIZE)),
        index: index
    )
}

private func utxo(_ in0: TransactionInput, address: Address, coin: Int64 = 2_000_000) -> UTxO {
    UTxO(input: in0, output: TransactionOutput(address: address, amount: Value(coin: coin)))
}

private func phaseTwo() -> PhaseTwo {
    PhaseTwo(costModel: .placeholder())
}

@Suite("PhaseTwo — additional coverage")
struct PhaseTwoCoverageTests {

    // MARK: — No redeemers

    @Test("transaction with no redeemers evaluates successfully with no results")
    func noRedeemers_succeedsEmpty() async throws {
        let body = TransactionBody(inputs: .list([input()]), outputs: [], fee: 0)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let result = try await phaseTwo().evaluate(transaction: tx, resolvedInputs: [])

        #expect(result.redeemers.isEmpty)
        #expect(result.success)  // allSatisfy over an empty set is true
    }

    // MARK: — Mint redeemer paths

    @Test("mint redeemer with no mint field fails with a type error")
    func mintRedeemer_noMintField_fails() async throws {
        let body = TransactionBody(inputs: .list([input()]), outputs: [], fee: 0)
        let redeemer = Redeemer(tag: .mint, index: 0, data: .bigInt(.int(0)))
        let witnesses = TransactionWitnessSet(redeemers: .list([redeemer]))
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnesses)

        let result = try await phaseTwo().evaluate(transaction: tx, resolvedInputs: [])

        #expect(result.redeemers.count == 1)
        #expect(!result.success)
        let r = try #require(result.redeemers.first)
        guard case .typeError(let message) = r.error else {
            Issue.record("Expected typeError, got \(String(describing: r.error))")
            return
        }
        #expect(message.contains("no mint field"))
    }

    @Test("mint redeemer with a policy but no matching script fails with a type error")
    func mintRedeemer_noMatchingScript_fails() async throws {
        let policyId = ScriptHash(payload: Data(repeating: 0xCC, count: SCRIPT_HASH_SIZE))
        let mint = MultiAsset([policyId: Asset([AssetName(from: "TOKEN"): 1])])
        let body = TransactionBody(inputs: .list([input()]), outputs: [], fee: 0, mint: mint)
        let redeemer = Redeemer(tag: .mint, index: 0, data: .bigInt(.int(0)))
        let witnesses = TransactionWitnessSet(redeemers: .list([redeemer]))
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnesses)

        let result = try await phaseTwo().evaluate(transaction: tx, resolvedInputs: [])

        let r = try #require(result.redeemers.first)
        #expect(!r.passed)
        guard case .typeError(let message) = r.error else {
            Issue.record("Expected typeError, got \(String(describing: r.error))")
            return
        }
        #expect(message.contains("no script found"))
    }

    @Test("mint redeemer index out of range fails with a type error")
    func mintRedeemer_indexOutOfRange_fails() async throws {
        let policyId = ScriptHash(payload: Data(repeating: 0xCC, count: SCRIPT_HASH_SIZE))
        let mint = MultiAsset([policyId: Asset([AssetName(from: "TOKEN"): 1])])
        let body = TransactionBody(inputs: .list([input()]), outputs: [], fee: 0, mint: mint)
        let redeemer = Redeemer(tag: .mint, index: 5, data: .bigInt(.int(0)))
        let witnesses = TransactionWitnessSet(redeemers: .list([redeemer]))
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnesses)

        let result = try await phaseTwo().evaluate(transaction: tx, resolvedInputs: [])

        let r = try #require(result.redeemers.first)
        #expect(!r.passed)
        guard case .typeError(let message) = r.error else {
            Issue.record("Expected typeError, got \(String(describing: r.error))")
            return
        }
        #expect(message.contains("out of range"))
    }

    // MARK: — Spend redeemer at a non-script address

    @Test("resolved spend input at a vkey (non-script) address fails with a type error")
    func spendRedeemer_nonScriptAddress_fails() async throws {
        let spent = input(0x01)
        let resolved = utxo(spent, address: try vkeyAddr())
        let body = TransactionBody(inputs: .list([spent]), outputs: [], fee: 0)
        let redeemer = Redeemer(tag: .spend, index: 0, data: .bigInt(.int(0)))
        let witnesses = TransactionWitnessSet(redeemers: .list([redeemer]))
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnesses)

        let result = try await phaseTwo().evaluate(transaction: tx, resolvedInputs: [resolved])

        let r = try #require(result.redeemers.first)
        #expect(!r.passed)
        guard case .typeError(let message) = r.error else {
            Issue.record("Expected typeError, got \(String(describing: r.error))")
            return
        }
        #expect(message.contains("not a script address"))
    }

    @Test("resolved spend input at a script address but with no script witness fails")
    func spendRedeemer_scriptAddressNoWitness_fails() async throws {
        let spent = input(0x01)
        let resolved = utxo(spent, address: try scriptAddr())
        let body = TransactionBody(inputs: .list([spent]), outputs: [], fee: 0)
        let redeemer = Redeemer(tag: .spend, index: 0, data: .bigInt(.int(0)))
        let witnesses = TransactionWitnessSet(redeemers: .list([redeemer]))
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnesses)

        let result = try await phaseTwo().evaluate(transaction: tx, resolvedInputs: [resolved])

        let r = try #require(result.redeemers.first)
        #expect(!r.passed)
        guard case .typeError(let message) = r.error else {
            Issue.record("Expected typeError, got \(String(describing: r.error))")
            return
        }
        #expect(message.contains("no script found"))
    }

    // MARK: — Redeemers that point at nothing

    @Test("A certificate redeemer with no certificate to point at is rejected")
    func certRedeemer_outOfRange() async throws {
        let body = TransactionBody(inputs: .list([input()]), outputs: [], fee: 0)
        let redeemer = Redeemer(tag: .cert, index: 0, data: .bigInt(.int(0)))
        let witnesses = TransactionWitnessSet(redeemers: .list([redeemer]))
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnesses)

        let result = try await phaseTwo().evaluate(transaction: tx, resolvedInputs: [])

        let r = try #require(result.redeemers.first)
        #expect(!r.passed)
        guard case .typeError(let message) = r.error else {
            Issue.record("Expected typeError, got \(String(describing: r.error))")
            return
        }
        #expect(message.contains("out of range"))
    }

    // MARK: — Map-form redeemers

    @Test("map-form redeemers keep the tag and index from their key")
    func mapFormRedeemers_areEvaluated() async throws {
        var redeemerMap = RedeemerMap()
        redeemerMap[RedeemerKey(tag: .mint, index: 0)] =
            RedeemerValue(data: .bigInt(.int(0)), exUnits: ExecutionUnits(mem: 1, steps: 1))
        let body = TransactionBody(inputs: .list([input()]), outputs: [], fee: 0)
        let witnesses = TransactionWitnessSet(redeemers: .map(redeemerMap))
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnesses)

        let result = try await phaseTwo().evaluate(transaction: tx, resolvedInputs: [])

        #expect(result.redeemers.count == 1)
        #expect(!result.success)
        let r = try #require(result.redeemers.first)
        // The mint tag survives the map encoding, so findScript takes the mint
        // branch and fails on the absent mint field rather than on a nil tag.
        guard case .typeError(let message) = r.error else {
            Issue.record("Expected typeError, got \(String(describing: r.error))")
            return
        }
        #expect(message.contains("mint redeemer but no mint field"))
        #expect(!message.contains("not yet supported"))
    }

    @Test("map-form spend redeemers resolve their input via the key's index")
    func mapFormSpendRedeemers_useKeyIndex() async throws {
        // Two inputs; the redeemer key points at index 1. If the index were
        // dropped, this would resolve input 0 instead.
        let in0 = input(0x01)
        let in1 = input(0x02)
        var redeemerMap = RedeemerMap()
        redeemerMap[RedeemerKey(tag: .spend, index: 1)] =
            RedeemerValue(data: .bigInt(.int(0)), exUnits: ExecutionUnits(mem: 1, steps: 1))
        let body = TransactionBody(inputs: .list([in0, in1]), outputs: [], fee: 0)
        let witnesses = TransactionWitnessSet(redeemers: .map(redeemerMap))
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnesses)

        let result = try await phaseTwo().evaluate(transaction: tx, resolvedInputs: [])

        let r = try #require(result.redeemers.first)
        #expect(!r.passed)
        guard case .typeError(let message) = r.error else {
            Issue.record("Expected typeError, got \(String(describing: r.error))")
            return
        }
        // Unresolvable spend input is reported against the input the key names.
        #expect(message.contains("\(in1)"))
    }

    // MARK: — Mixed redeemers preserve ordering

    @Test("mixed resolvable and unresolvable redeemers all report, sorted by index")
    func mixedRedeemers_sortedByIndex() async throws {
        // index 0: spend, unresolvable (no resolved input)
        // index 1: cert, unsupported
        let in0 = input(0x01)
        let in1 = input(0x02)
        let body = TransactionBody(inputs: .list([in0, in1]), outputs: [], fee: 0)
        let redeemers: [any RedeemerProtocol] = [
            Redeemer(tag: .spend, index: 0, data: .bigInt(.int(0))),
            Redeemer(tag: .cert, index: 1, data: .bigInt(.int(0))),
        ]
        let witnesses = TransactionWitnessSet(redeemers: .list(redeemers))
        let tx = Transaction(transactionBody: body, transactionWitnessSet: witnesses)

        let result = try await phaseTwo().evaluate(transaction: tx, resolvedInputs: [])

        #expect(result.redeemers.map(\.index) == [0, 1])
        #expect(!result.success)
        #expect(result.redeemers.allSatisfy { !$0.passed })
    }

    // MARK: — Convenience initializer

    /// Protocol parameters carrying no cost model used to be accepted
    /// silently, handing back a placeholder whose budgets meant nothing.
    @Test("protocol-parameters initializer rejects parameters with no cost model")
    func protocolParamsInit_rejectsEmptyCostModel() throws {
        #expect(throws: CostModelError.missingCostModel(.v2)) {
            try PhaseTwo(protocolParameters: dummyProtocolParametersForCoverage(), version: .v2)
        }
    }

    @Test("placeholder cost model builds a usable PhaseTwo")
    func placeholderInit_works() async throws {
        let pt = PhaseTwo(costModel: .placeholder())
        let body = TransactionBody(inputs: .list([input()]), outputs: [], fee: 0)
        let tx = Transaction(transactionBody: body, transactionWitnessSet: TransactionWitnessSet())

        let result = try await pt.evaluate(transaction: tx, resolvedInputs: [])
        #expect(result.redeemers.isEmpty)
        #expect(result.success)
    }
}

// MARK: — Protocol parameters fixture

private func dummyProtocolParametersForCoverage() -> ProtocolParameters {
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
