# ``SwiftCardanoUPLC/PhaseTwo``

Evaluate all Plutus scripts in a Cardano transaction (Phase-2 validation).

## Overview

`PhaseTwo` orchestrates the evaluation of every Plutus redeemer in a transaction. Each script runs in its own concurrent `Task` so scripts do not block each other.

The evaluation pipeline for each redeemer is:

1. Locate the script (from the witness set or reference inputs).
2. Unwrap the CBOR envelope and decode the flat-encoded ``NamedDeBruijnProgram``.
3. Build the appropriate ``ScriptContext`` (spending or minting).
4. Apply datum (V1/V2 spending), redeemer, and script context as arguments.
5. Run the ``CEKMachine`` with the on-chain budget from the chain context.

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
| `.spend` | V1/V2: datum + redeemer + context. V3: redeemer + context only. |
| `.mint` | Redeemer + minting context. |

Reward, cert, and vote redeemers are not yet supported and will throw a ``MachineError``.

## Topics

### Running validation

- ``evaluate(transaction:resolvedInputs:)``

### Results

- ``PhaseTwoResult``
- ``RedeemerResult``
