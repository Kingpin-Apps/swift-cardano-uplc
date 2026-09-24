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

### Validity intervals

A script sees a transaction's validity interval as POSIX milliseconds, but a
transaction states it in slots — so evaluating one needs to know when the chain's
slots happen. That is what `SlotTimeline` is for:

```swift
let phaseTwo = try PhaseTwo(protocolParameters: pp, slotTimeline: .mainnet)
```

Slots are not a uniform grid. Mainnet's Byron era ran on twenty-second slots and
everything since Shelley runs on one-second slots, so reading a present-day slot
as `systemStart + slot` puts it about two and a half years early. `SlotTimeline`
knows the boundaries; `SlotTimeline(systemStart:eraHistory:)` reads them from
whatever a node reports, for a network it has no built-in answer for.

The interval keeps the asymmetry a transaction's own bounds have. `invalid_before`
includes its slot and becomes a **closed** lower bound; `invalid_hereafter`
excludes its and becomes a **strict** upper one. A script comparing against a
deadline therefore sees the first instant the transaction is no longer valid,
not the last one it is.

Without a timeline, a transaction that has an interval is refused rather than
handed the unbounded one — which would quietly defeat every deadline check the
script makes.

### Transactions the script context cannot represent

A context that is subtly wrong makes a correct script look broken, so the builder
refuses rather than approximating. ``ScriptContextError/unsupportedFeature(_:)`` is
raised for a spending input missing from `resolvedInputs`, since dropping it would
show the script a transaction that spends less than the real one, and for a
validity interval with no ``SlotTimeline`` to read it with.

Pass every input the transaction references, including reference inputs: a script
spending through a reference script has no script in its witness set at all.

### What V1 and V2 see

V1 and V2 do not see a smaller V3 context, they see a different one, and the
differences are easy to miss:

| | V1 | V2 | V3 |
|---|---|---|---|
| `TxInfo` fields | 10 | 12 | 16 |
| `fee` | a `Value` | a `Value` | an integer |
| `id` | `Constr 0 [bytes]` | same | raw bytes |
| `mint` | carries a **zero-ada entry**, always | same | never has one |
| `withdrawals` | a list of pairs | a map | a map |
| `datums` | a list of pairs | a map | a map |
| `redeemers` | *absent* | a map | a map |
| an output's datum | a `Maybe` hash | `OutputDatum` | `OutputDatum` |
| certificates | the smaller `DCert` | same | `TxCert` |

Two orderings are worth calling out, because a context can hold both at once:

- **Withdrawals** reach a V1 or V2 script in *Plutus's* credential order, which
  puts a key credential before a script one, and a V3 script in the *ledger's*,
  which is the reverse. A reward redeemer's *index* counts in the ledger's order
  in all three, because that is what the redeemer pointer is resolved against.
- **Datums** are ordered by datum hash, not by the order the witness set lists
  them in.

### How a builtin is priced depends on the protocol version

Plutus calls this a builtin semantics *variant*, and it depends on the language
and the protocol version together: V1 and V2 are priced by variant A up to the
Chang hard fork and variant B since, while V3 uses variant C. Variant B charges
`multiplyInteger` by the *product* of its argument sizes where A charges by their
*sum*, and prices `verifyEd25519Signature` by the size of the message rather than
the signature.

Plutus also defines variants D and E for a later hard fork. They are deliberately
not used here: mainnet at major version 11 still prices V3 by variant C, which a
transaction calling `divideInteger` nine times and `modInteger` nineteen times
confirms to the step.

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

Units are still worth checking, from the other end. `MainnetExUnitsTests` runs real
mainnet transactions and compares against the units they declare on chain — the
budget the ledger actually charged. A byte-exact context and a matching budget
together cover both the context and the machine that runs on it, and they catch
different things: the cost-model conformance corpus only pins V3, so V1 and V2
being priced by the wrong semantics variant showed up nowhere until a real
withdrawal script came out a flat 4,152 steps over.

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
