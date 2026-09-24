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

Reward, cert, vote and propose redeemers are not supported yet and throw a
``MachineError``.

### Transactions the script context cannot represent

A context that is subtly wrong makes a correct script look broken, so the builder
refuses rather than approximating. ``ScriptContextError/unsupportedFeature(_:)`` is
raised for a transaction that carries certificates, voting procedures or proposal
procedures, for one with a validity interval (converting slots to POSIX time needs
era history the builder is not given), and for a spending input missing from
`resolvedInputs` — dropping it would show the script a transaction that spends less
than the real one.

Pass every input the transaction references, including reference inputs: a script
spending through a reference script has no script in its witness set at all.

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
