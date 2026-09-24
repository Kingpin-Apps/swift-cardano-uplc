# ``SwiftCardanoUPLC/PhaseTwo``

Evaluate all Plutus scripts in a Cardano transaction (Phase-2 validation).

## Overview

`PhaseTwo` orchestrates the evaluation of every Plutus redeemer in a transaction. Each script runs in its own concurrent `Task` so scripts do not block each other.

The evaluation pipeline for each redeemer is:

1. Locate the script (from the witness set or reference inputs).
2. Unwrap the CBOR envelope and decode the flat-encoded ``NamedDeBruijnProgram``.
3. Build the appropriate ``ScriptContext`` (spending or minting).
4. Apply the script's arguments: V1/V2 take datum (spending only), redeemer and
   context; V3 takes the context alone, because it carries both the redeemer and
   the datum.
5. Run the ``CEKMachine`` with the cost model for that script's Plutus version.

### Usage

```swift
import SwiftCardanoUPLC

let pp       = try await chainContext.protocolParameters()
let phaseTwo = try PhaseTwo(protocolParameters: pp)
let result   = try await phaseTwo.evaluate(
    transaction: tx,
    resolvedInputs: resolvedUTxOs   // all inputs + reference inputs
)

guard result.success else {
    for r in result.redeemers where !r.passed {
        print("Redeemer \(r.index) failed: \(r.error!)")
    }
    return
}
print("All scripts passed. Remaining budgets: \(result.redeemers.map(\.remainingBudget))")
```

### Supported redeemer tags

| Tag | Notes |
|-----|-------|
| `.spend` | V1/V2 receive datum, redeemer and context. V3 receives the context alone. |
| `.mint` | V1/V2 receive redeemer and context. V3 receives the context alone. |
| `.reward` | A script withdrawal. V1/V2 name the purpose `Rewarding` and wrap the credential in `StakingHash`; V3 names it `Withdrawing` and keys it by the bare `Credential`. |
| `.cert` | A certificate acting on a script credential. V3 names the purpose `Publishing` and gives it the certificate *and its index*; V1/V2 name it `Certifying` and see only the certificate, in the smaller `DCert` shape. |
| `.voting` | A vote cast by a script — a DRep or a committee hot credential that is a script. Conway only: V1 and V2 have no such purpose. |
| `.proposing` | The guardrails script named by a proposal's policy hash, which only a parameter change or a treasury withdrawal carries. Conway only. |

An index always counts through the transaction in the ledger's own order for that
kind of thing, and getting it wrong points the script at the wrong item:

- a **reward** index counts the withdrawals in reward-account order, which places
  script credentials before key ones;
- a **certificate** index counts the certificates in the order the transaction
  lists them, not in any sorted order;
- a **vote** index counts the voters in the ledger's order — by role first
  (committee, then DRep, then stake pool), then script credentials before key
  ones;
- a **proposal** index counts the proposals as written.

Pointing a redeemer at something that needs a signature rather than a script — a
key-credential withdrawal, a pool certificate, a stake-pool voter — is an error,
as is a proposal that names no guardrails script.

### Certificates a script can see

PlutusV3 has eleven certificate constructors and the ledger has nineteen
certificates, so several land on the same one: a registration with a deposit and
one without are both `RegisterCredential`, and all three delegation certificates
are `DelegateCredential` carrying a different `Delegate`.

One field depends on the protocol version. A registration's deposit was dropped
from the script context by a bug during the Conway bootstrap, at major version 9,
and because transactions relying on that reached mainnet the ledger keeps the
behaviour for that version forever. From version 10 on the deposit is visible.
``PhaseTwo/init(protocolParameters:version:)`` takes the version from the
parameters; ``PhaseTwo/init(costModel:protocolMajorVersion:)`` needs telling.

PlutusV1 and V2 predate Conway and see only the five Shelley certificates. A
transaction that carries a Conway-only certificate alongside a V1 or V2 script is
rejected by the ledger, and rejected here too rather than approximated.

### Transactions the script context cannot represent

A context that is subtly wrong makes a correct script look broken, so the builder
refuses rather than approximating. ``ScriptContextError/unsupportedFeature(_:)`` is
raised for a transaction with a validity interval — converting slots to POSIX
milliseconds needs the era history and genesis parameters the builder is not
given, and substituting the unbounded interval would quietly defeat every
deadline check in the script — and for a spending input missing from
`resolvedInputs`, since dropping it would show the script a transaction that
spends less than the real one.

Pass every input the transaction references, including reference inputs: a script
spending through a reference script has no script in its witness set at all.

### Checking the context against the ledger

The context is compared against the ledger's own, byte for byte, in
`LedgerScriptContextTests`. Each fixture comes from
`cardano-cli conway transaction calculate-plutus-script-cost offline`, which
reports the arguments it handed a script when that script fails — so a validator
that returns `False` makes the node print the context it built.

Matching execution units is a much weaker check, and it is worth knowing why: the
budget only reflects the parts of the context a script actually looks at, so a
field in the wrong order or missing outright costs nothing and goes unnoticed. The
redeemer map was in the wrong order while every budget still matched exactly.

### Execution budgets

Each script is costed with the model for its own Plutus version. When `PhaseTwo` is
built from a placeholder cost model there is no meaningful budget, so evaluation runs
unmetered and ``RedeemerResult/budgetMeasured`` is `false`; treat the budget as absent
rather than as execution units.

## Topics

### Running validation

- ``evaluate(transaction:resolvedInputs:)``

### Results

- ``PhaseTwoResult``
- ``RedeemerResult``
