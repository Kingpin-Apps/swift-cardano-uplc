import Foundation
import SwiftCardanoCore

// Certificates as a script sees them.
//
// The ledger has nineteen certificate variants and Plutus has eleven, so
// several ledger certificates land on the same Plutus constructor — a
// registration with a deposit and one without are both `RegisterCredential`,
// and all three delegation certificates are `DelegateCredential` with a
// different `Delegate`. The mapping below is the ledger's `transTxCert`.

/// The Plutus V3 `Certificate` for a ledger certificate.
///
/// Constructor order is the ledger's: `RegisterCredential`(0),
/// `UnregisterCredential`(1), `DelegateCredential`(2),
/// `RegisterAndDelegateCredential`(3), `RegisterDelegateRepresentative`(4),
/// `UpdateDelegateRepresentative`(5), `UnregisterDelegateRepresentative`(6),
/// `RegisterStakePool`(7), `RetireStakePool`(8),
/// `AuthorizeConstitutionalCommitteeProxy`(9),
/// `RetireFromConstitutionalCommittee`(10).
///
/// - Parameter protocolMajorVersion: decides whether a registration's deposit
///   is visible. During the Conway bootstrap (major version 9) the ledger had a
///   bug that dropped it, and because that behaviour reached mainnet it can
///   never be removed — so the deposit shows as `None` at version 9 and as
///   `Some` from version 10 on.
func certificateDataV3(
    _ certificate: Certificate,
    protocolMajorVersion: Int
) throws -> PlutusData {
    /// The deposit the ledger reveals for a registration or deregistration.
    func deposit(_ coin: Coin) -> PlutusData {
        maybeData(protocolMajorVersion >= 10 ? .bigInt(.int(Int64(coin))) : nil)
    }

    switch certificate {
        case .stakeRegistration(let cert):
            // The pre-Conway form carries no deposit at all.
            return constr(0, [try credentialData(cert.stakeCredential), maybeData(nil)])

        case .register(let cert):
            return constr(0, [try credentialData(cert.stakeCredential), deposit(cert.coin)])

        case .stakeDeregistration(let cert):
            return constr(1, [try credentialData(cert.stakeCredential), maybeData(nil)])

        case .unregister(let cert):
            return constr(1, [try credentialData(cert.stakeCredential), deposit(cert.coin)])

        case .stakeDelegation(let cert):
            return constr(2, [
                try credentialData(cert.stakeCredential),
                try delegateToStakePool(cert.poolKeyHash),
            ])

        case .voteDelegate(let cert):
            return constr(2, [
                try credentialData(cert.stakeCredential),
                try delegateToRepresentative(cert.drep),
            ])

        case .stakeVoteDelegate(let cert):
            return constr(2, [
                try credentialData(cert.stakeCredential),
                try delegateToBoth(cert.poolKeyHash, cert.drep),
            ])

        case .stakeRegisterDelegate(let cert):
            return constr(3, [
                try credentialData(cert.stakeCredential),
                try delegateToStakePool(cert.poolKeyHash),
                .bigInt(.int(Int64(cert.coin))),
            ])

        case .voteRegisterDelegate(let cert):
            return constr(3, [
                try credentialData(cert.stakeCredential),
                try delegateToRepresentative(cert.drep),
                .bigInt(.int(Int64(cert.coin))),
            ])

        case .stakeVoteRegisterDelegate(let cert):
            return constr(3, [
                try credentialData(cert.stakeCredential),
                try delegateToBoth(cert.poolKeyHash, cert.drep),
                .bigInt(.int(Int64(cert.coin))),
            ])

        case .registerDRep(let cert):
            // The anchor is not part of the script's view.
            return constr(4, [
                try credentialData(cert.drepCredential),
                .bigInt(.int(Int64(cert.coin))),
            ])

        case .updateDRep(let cert):
            return constr(5, [try credentialData(cert.drepCredential)])

        case .unRegisterDRep(let cert):
            return constr(6, [
                try credentialData(cert.drepCredential),
                .bigInt(.int(Int64(cert.coin))),
            ])

        case .poolRegistration(let cert):
            // Only the pool's own id and its VRF key reach the script; the
            // pledge, margin, relays and metadata do not.
            return constr(7, [
                .bytes(try Bytes(from: cert.poolParams.poolOperator.payload)),
                .bytes(try Bytes(from: cert.poolParams.vrfKeyHash.payload)),
            ])

        case .poolRetirement(let cert):
            return constr(8, [
                .bytes(try Bytes(from: cert.poolKeyHash.payload)),
                .bigInt(.int(Int64(cert.epoch))),
            ])

        case .authCommitteeHot(let cert):
            return constr(9, [
                try credentialData(cert.committeeColdCredential),
                try credentialData(cert.committeeHotCredential),
            ])

        case .resignCommitteeCold(let cert):
            return constr(10, [try credentialData(cert.committeeColdCredential)])

        case .genesisKeyDelegation, .moveInstantaneousRewards:
            // Both were dropped in Conway, so no Conway transaction can carry
            // one and Plutus V3 has no constructor for them.
            throw ScriptContextError.unsupportedFeature(
                "\(certificateName(certificate)) is not a Conway certificate and has no "
                + "PlutusV3 representation."
            )
    }
}

/// The Plutus V1/V2 `DCert` for a ledger certificate.
///
/// V1 and V2 predate Conway governance, so they see only the five Shelley
/// certificates; the Conway registration and deregistration forms collapse onto
/// the Shelley ones with their deposit dropped. Anything else is rejected by
/// the ledger rather than approximated, and so is rejected here.
func certificateDataV1V2(_ certificate: Certificate) throws -> PlutusData {
    /// V1 and V2 key a certificate by `StakingCredential`, which wraps the
    /// credential in `StakingHash`.
    func stakingHash(_ credential: some SwiftCardanoCore.Credential) throws -> PlutusData {
        constr(0, [try credentialData(credential)])
    }

    switch certificate {
        case .stakeRegistration(let cert):
            return constr(0, [try stakingHash(cert.stakeCredential)])
        case .register(let cert):
            return constr(0, [try stakingHash(cert.stakeCredential)])
        case .stakeDeregistration(let cert):
            return constr(1, [try stakingHash(cert.stakeCredential)])
        case .unregister(let cert):
            return constr(1, [try stakingHash(cert.stakeCredential)])
        case .stakeDelegation(let cert):
            return constr(2, [
                try stakingHash(cert.stakeCredential),
                .bytes(try Bytes(from: cert.poolKeyHash.payload)),
            ])
        case .poolRegistration(let cert):
            return constr(3, [
                .bytes(try Bytes(from: cert.poolParams.poolOperator.payload)),
                .bytes(try Bytes(from: cert.poolParams.vrfKeyHash.payload)),
            ])
        case .poolRetirement(let cert):
            return constr(4, [
                .bytes(try Bytes(from: cert.poolKeyHash.payload)),
                .bigInt(.int(Int64(cert.epoch))),
            ])
        default:
            throw ScriptContextError.unsupportedFeature(
                "\(certificateName(certificate)) has no PlutusV1 or V2 representation; the "
                + "ledger rejects a transaction that carries one alongside a V1 or V2 script."
            )
    }
}

/// `Delegate.DelegateBlockProduction`.
private func delegateToStakePool(_ poolKeyHash: PoolKeyHash) throws -> PlutusData {
    constr(0, [.bytes(try Bytes(from: poolKeyHash.payload))])
}

/// `Delegate.DelegateVote`.
private func delegateToRepresentative(_ drep: DRep) throws -> PlutusData {
    constr(1, [try delegateRepresentativeData(drep)])
}

/// `Delegate.DelegateBoth`.
private func delegateToBoth(_ poolKeyHash: PoolKeyHash, _ drep: DRep) throws -> PlutusData {
    constr(2, [
        .bytes(try Bytes(from: poolKeyHash.payload)),
        try delegateRepresentativeData(drep),
    ])
}

/// `DelegateRepresentative` — `Registered`(0) wraps a credential, and the two
/// standing options carry nothing.
func delegateRepresentativeData(_ drep: DRep) throws -> PlutusData {
    switch drep.credential {
        case .verificationKeyHash(let hash):
            return constr(0, [try credentialData(hash: hash.payload, isScript: false)])
        case .scriptHash(let hash):
            return constr(0, [try credentialData(hash: hash.payload, isScript: true)])
        case .alwaysAbstain:
            return constr(1, [])
        case .alwaysNoConfidence:
            return constr(2, [])
    }
}

/// Names a certificate the way the ledger's CDDL does, for error messages.
private func certificateName(_ certificate: Certificate) -> String {
    switch certificate {
        case .stakeRegistration: return "stake_registration"
        case .stakeDeregistration: return "stake_deregistration"
        case .stakeDelegation: return "stake_delegation"
        case .poolRegistration: return "pool_registration"
        case .poolRetirement: return "pool_retirement"
        case .genesisKeyDelegation: return "genesis_key_delegation"
        case .moveInstantaneousRewards: return "move_instantaneous_rewards"
        case .register: return "reg_cert"
        case .unregister: return "unreg_cert"
        case .voteDelegate: return "vote_deleg_cert"
        case .stakeVoteDelegate: return "stake_vote_deleg_cert"
        case .stakeRegisterDelegate: return "stake_reg_deleg_cert"
        case .voteRegisterDelegate: return "vote_reg_deleg_cert"
        case .stakeVoteRegisterDelegate: return "stake_vote_reg_deleg_cert"
        case .authCommitteeHot: return "auth_committee_hot_cert"
        case .resignCommitteeCold: return "resign_committee_cold_cert"
        case .registerDRep: return "reg_drep_cert"
        case .unRegisterDRep: return "unreg_drep_cert"
        case .updateDRep: return "update_drep_cert"
    }
}
