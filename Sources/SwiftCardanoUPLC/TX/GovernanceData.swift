import Foundation
import OrderedCollections
import SwiftCardanoCore

// Conway governance as a script sees it: voters and their votes, and the
// proposal procedures a guardrails script is asked to approve.
//
// Two things here are easy to get wrong. Ledger maps reach Plutus in the
// ledger's own key order, which for a credential puts script hashes *before*
// key hashes and groups voters by role before either. And every ratio is
// reduced before it is handed over, because the ledger converts through a
// Haskell `Ratio` on the way — so 2/4 arrives as 1/2.

/// `Voter` — `ConstitutionalCommitteeMember`(0) and
/// `DelegateRepresentative`(1) carry a `Credential`, while `StakePool`(2)
/// carries a bare key hash.
func voterData(_ voter: Voter) throws -> PlutusData {
    switch voter.credential {
        case .constitutionalCommitteeHotKeyhash(let hash):
            return constr(0, [try credentialData(hash: hash.payload, isScript: false)])
        case .constitutionalCommitteeHotScriptHash(let hash):
            return constr(0, [try credentialData(hash: hash.payload, isScript: true)])
        case .drepKeyhash(let hash):
            return constr(1, [try credentialData(hash: hash.payload, isScript: false)])
        case .drepScriptHash(let hash):
            return constr(1, [try credentialData(hash: hash.payload, isScript: true)])
        case .stakePoolKeyhash(let hash):
            return constr(2, [.bytes(try Bytes(from: hash.payload))])
    }
}

/// A voter's place in the ledger's ordering: its role, then a script
/// credential before a key credential, then the hash itself.
func voterSortKey(_ voter: Voter) -> (role: Int, isKey: Bool, hash: Data) {
    switch voter.credential {
        case .constitutionalCommitteeHotScriptHash(let hash): return (0, false, hash.payload)
        case .constitutionalCommitteeHotKeyhash(let hash): return (0, true, hash.payload)
        case .drepScriptHash(let hash): return (1, false, hash.payload)
        case .drepKeyhash(let hash): return (1, true, hash.payload)
        case .stakePoolKeyhash(let hash): return (2, true, hash.payload)
    }
}

/// `Vote` — `No`(0), `Yes`(1), `Abstain`(2).
func voteData(_ vote: Vote) -> PlutusData {
    constr(UInt64(vote.rawValue), [])
}

/// `GovernanceActionId` — the proposing transaction's id as raw bytes, and the
/// proposal's index within it.
func governanceActionIdData(_ id: GovActionID) throws -> PlutusData {
    constr(0, [
        .bytes(try Bytes(from: id.transactionID.payload)),
        .bigInt(.int(Int64(id.govActionIndex))),
    ])
}

/// `votes: Pairs<Voter, Pairs<GovernanceActionId, Vote>>`, in the ledger's order.
func votesData(_ procedures: VotingProcedures?) throws -> PlutusData {
    guard let procedures, !procedures.isEmpty else { return .map([:]) }

    var byVoter: [Data: [(id: GovActionID, vote: Vote)]] = [:]
    var voters: [Voter] = []
    for (voter, id, procedure) in procedures.allVotes {
        let key = try voter.toCBORData()
        if byVoter[key] == nil {
            byVoter[key] = []
            voters.append(voter)
        }
        byVoter[key]?.append((id, procedure.vote))
    }

    var map = OrderedDictionary<PlutusData, PlutusData>()
    for voter in voters.sorted(by: { lhs, rhs in
        let (lhsKey, rhsKey) = (voterSortKey(lhs), voterSortKey(rhs))
        if lhsKey.role != rhsKey.role { return lhsKey.role < rhsKey.role }
        if lhsKey.isKey != rhsKey.isKey { return !lhsKey.isKey }
        return lhsKey.hash.lexicographicallyPrecedes(rhsKey.hash)
    }) {
        let votes = (byVoter[try voter.toCBORData()] ?? []).sorted { lhs, rhs in
            if lhs.id.transactionID.payload != rhs.id.transactionID.payload {
                return lhs.id.transactionID.payload
                    .lexicographicallyPrecedes(rhs.id.transactionID.payload)
            }
            return lhs.id.govActionIndex < rhs.id.govActionIndex
        }
        var inner = OrderedDictionary<PlutusData, PlutusData>()
        for vote in votes {
            inner[try governanceActionIdData(vote.id)] = voteData(vote.vote)
        }
        map[try voterData(voter)] = inner.isEmpty ? .map([:]) : .map(inner)
    }
    return map.isEmpty ? .map([:]) : .map(map)
}

/// `ProposalProcedure { deposit, return_address, governance_action }`.
///
/// The anchor — the off-chain metadata the proposal points at — is not part of
/// what a script sees, and the return address reaches it as a bare
/// `Credential` with its network dropped.
func proposalProcedureData(
    _ proposal: ProposalProcedure,
    protocolMajorVersion: Int
) throws -> PlutusData {
    constr(0, [
        .bigInt(.int(Int64(proposal.deposit))),
        try rewardAccountCredentialData(proposal.rewardAccount),
        try governanceActionData(proposal.govAction, protocolMajorVersion: protocolMajorVersion),
    ])
}

/// `GovernanceAction` — `ProtocolParameters`(0), `HardFork`(1),
/// `TreasuryWithdrawal`(2), `NoConfidence`(3), `ConstitutionalCommittee`(4),
/// `NewConstitution`(5), `NicePoll`(6).
func governanceActionData(
    _ action: GovAction,
    protocolMajorVersion: Int
) throws -> PlutusData {
    switch action {
        case .parameterChangeAction(let action):
            return constr(0, [
                maybeData(try action.id.map { try governanceActionIdData($0) }),
                try changedParametersData(action.protocolParamUpdate),
                maybeData(try action.policyHash.map { .bytes(try Bytes(from: $0.payload)) }),
            ])

        case .hardForkInitiationAction(let action):
            return constr(1, [
                maybeData(try action.id.map { try governanceActionIdData($0) }),
                constr(0, [
                    .bigInt(.int(Int64(action.protocolVersion.major ?? 0))),
                    .bigInt(.int(Int64(action.protocolVersion.minor ?? 0))),
                ]),
            ])

        case .treasuryWithdrawalsAction(let action):
            var map = OrderedDictionary<PlutusData, PlutusData>()
            for (account, coin) in orderedRewardAccounts(action.withdrawals) {
                map[try rewardAccountCredentialData(account)] = .bigInt(.int(Int64(coin)))
            }
            return constr(2, [
                map.isEmpty ? .map([:]) : .map(map),
                maybeData(try action.policyHash.map { .bytes(try Bytes(from: $0.payload)) }),
            ])

        case .noConfidence(let action):
            return constr(3, [
                maybeData(try action.id.map { try governanceActionIdData($0) })
            ])

        case .updateCommittee(let action):
            let evicted = try action.coldCredentials
                .sorted { CredentialType.ledgerOrder($0.credential, $1.credential) }
                .map { try credentialData($0) }
            var added = OrderedDictionary<PlutusData, PlutusData>()
            for (credential, epoch) in action.credentialEpochs
                .sorted(by: { CredentialType.ledgerOrder($0.key.credential, $1.key.credential) }) {
                added[try credentialData(credential)] = .bigInt(.int(Int64(epoch)))
            }
            return constr(4, [
                maybeData(try action.id.map { try governanceActionIdData($0) }),
                dataList(evicted),
                added.isEmpty ? .map([:]) : .map(added),
                rationalData(
                    numerator: action.interval.numerator,
                    denominator: action.interval.denominator
                ),
            ])

        case .newConstitution(let action):
            return constr(5, [
                maybeData(try action.id.map { try governanceActionIdData($0) }),
                // `Constitution` holds only the guardrails script; the anchor
                // the constitution text lives behind is not on chain.
                constr(0, [
                    maybeData(
                        try action.constitution.scriptHash
                            .map { .bytes(try Bytes(from: $0.payload)) }
                    )
                ]),
            ])

        case .infoAction:
            return constr(6, [])
    }
}

/// A reward account reaches a script as the bare `Credential` it wraps.
func rewardAccountCredentialData(_ account: RewardAccount) throws -> PlutusData {
    guard let header = account.first else {
        throw ScriptContextError.unsupportedFeature("A reward account cannot be empty.")
    }
    return try credentialData(hash: Data(account.dropFirst()), isScript: (header & 0x10) != 0)
}

/// Reward accounts in the ledger's order: script credentials first, then by hash.
func orderedRewardAccounts(_ withdrawals: [RewardAccount: Coin]) -> [(RewardAccount, Coin)] {
    withdrawals.sorted { lhs, rhs in
        let lhsIsScript = (lhs.key.first.map { $0 & 0x10 } ?? 0) != 0
        let rhsIsScript = (rhs.key.first.map { $0 & 0x10 } ?? 0) != 0
        if lhsIsScript != rhsIsScript { return lhsIsScript }
        return lhs.key.dropFirst().lexicographicallyPrecedes(rhs.key.dropFirst())
    }
}

/// A ratio, reduced. The ledger hands Plutus a Haskell `Ratio`, which is always
/// in lowest terms, so a threshold written as 2/4 on chain arrives as 1/2.
func rationalData(numerator: UInt64, denominator: UInt64) -> PlutusData {
    let divisor = greatestCommonDivisor(numerator, denominator)
    let (numerator, denominator) = divisor == 0
        ? (numerator, denominator)
        : (numerator / divisor, denominator / divisor)
    return constr(0, [.bigInt(.int(Int64(numerator))), .bigInt(.int(Int64(denominator)))])
}

/// The same ratio as a two-element list, which is how the ledger writes every
/// ratio *inside* a protocol parameter update — unlike a governance action's
/// own threshold, which is a `Rational` record.
func rationalListData(numerator: UInt64, denominator: UInt64) -> PlutusData {
    let divisor = greatestCommonDivisor(numerator, denominator)
    let (numerator, denominator) = divisor == 0
        ? (numerator, denominator)
        : (numerator / divisor, denominator / divisor)
    return dataList([.bigInt(.int(Int64(numerator))), .bigInt(.int(Int64(denominator)))])
}

private func greatestCommonDivisor(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
    var (lhs, rhs) = (lhs, rhs)
    while rhs != 0 { (lhs, rhs) = (rhs, lhs % rhs) }
    return lhs
}

/// `ProtocolParametersUpdate` — the proposed changes, keyed by the ledger's own
/// parameter number and holding only the parameters the proposal actually sets.
///
/// The type is a newtype over raw data, so the map is *not* wrapped in a
/// constructor. Keys come out in ascending order, which is the order the
/// ledger declares its parameters in.
///
/// Four numbers the CDDL still defines are missing on purpose: Conway dropped
/// `decentralizationConstant`(12), `extraEntropy`(13) and `minUTxOValue`(15)
/// from the parameters a proposal may change, and `protocolVersion`(14) moves
/// by hard fork rather than by parameter change. The ledger leaves all four out
/// of the script's view.
func changedParametersData(_ update: ProtocolParamUpdate) throws -> PlutusData {
    /// Every ratio inside a parameter update is a two-element list.
    func ratio(_ interval: UnitInterval) -> PlutusData {
        rationalListData(numerator: interval.numerator, denominator: interval.denominator)
    }
    func ratio(_ interval: NonNegativeInterval) -> PlutusData {
        rationalListData(numerator: interval.lowerBound, denominator: interval.upperBound)
    }
    func integer<T: BinaryInteger>(_ value: T) -> PlutusData {
        .bigInt(.int(Int64(value)))
    }
    func exUnits(_ units: ExUnits) -> PlutusData {
        dataList([integer(units.mem), integer(units.steps)])
    }

    var parameters: [(key: Int64, value: PlutusData)] = []
    func set(_ key: Int64, _ value: PlutusData?) {
        guard let value else { return }
        parameters.append((key, value))
    }

    set(0, update.minFeeA.map(integer))
    set(1, update.minFeeB.map(integer))
    set(2, update.maxBlockBodySize.map(integer))
    set(3, update.maxTransactionSize.map(integer))
    set(4, update.maxBlockHeaderSize.map(integer))
    set(5, update.keyDeposit.map(integer))
    set(6, update.poolDeposit.map(integer))
    set(7, update.maximumEpoch.map(integer))
    set(8, update.nOpt.map(integer))
    set(9, update.poolPledgeInfluence.map(ratio))
    set(10, update.expansionRate.map(ratio))
    set(11, update.treasuryGrowthRate.map(ratio))
    set(16, update.minPoolCost.map(integer))
    set(17, update.adaPerUtxoByte.map(integer))
    set(18, try update.costModels.map { try costModelsData($0) })
    set(19, update.executionCosts.map { dataList([ratio($0.memPrice), ratio($0.stepPrice)]) })
    set(20, update.maxTxExUnits.map(exUnits))
    set(21, update.maxBlockExUnits.map(exUnits))
    set(22, update.maxValueSize.map(integer))
    set(23, update.collateralPercentage.map(integer))
    set(24, update.maxCollateralInputs.map(integer))
    set(25, update.poolVotingThresholds.map { dataList($0.thresholds.map(ratio)) })
    set(26, update.drepVotingThresholds.map { dataList($0.thresholds.map(ratio)) })
    set(27, update.minCommitteeSize.map(integer))
    set(28, update.committeeTermLimit.map(integer))
    set(29, update.governanceActionValidityPeriod.map(integer))
    set(30, update.governanceActionDeposit.map(integer))
    set(31, update.drepDeposit.map(integer))
    set(32, update.drepInactivityPeriod.map(integer))
    set(33, update.minFeeRefScriptCoinsPerByte.map(ratio))

    var map = OrderedDictionary<PlutusData, PlutusData>()
    for parameter in parameters.sorted(by: { $0.key < $1.key }) {
        map[.bigInt(.int(parameter.key))] = parameter.value
    }
    return map.isEmpty ? .map([:]) : .map(map)
}

/// Cost models as a parameter update carries them: each language's numbers as a
/// plain list, keyed by the language's own number.
private func costModelsData(_ costModels: CostModels) throws -> PlutusData {
    var map = OrderedDictionary<PlutusData, PlutusData>()
    for (language, model) in [
        (Int64(0), costModels.plutusV1),
        (Int64(1), costModels.plutusV2),
        (Int64(2), costModels.plutusV3),
    ] {
        guard let model else { continue }
        map[.bigInt(.int(language))] = dataList(model.values.map { .bigInt(.int($0)) })
    }
    return map.isEmpty ? .map([:]) : .map(map)
}
