# ``SwiftCardanoUPLC/CEKMachine``

Evaluate UPLC programs using the Control/Environment/Continuation (CEK) machine.

## Overview

`CEKMachine` is the canonical Cardano UPLC evaluator. It accepts a ``NamedDeBruijnProgram`` — convert a parsed ``NamedProgram`` using ``DeBruijnConverter`` first — and returns an ``EvalResult`` containing the final term, remaining budget, and any trace log entries.

### Evaluation model

The machine operates on three kinds of state:

- **compute** — reduce a term in an environment under a continuation
- **returning** — thread a value back through the continuation stack
- **done** — discharge the final value back to a term and return it

### Execution budget

Every step deducts from an ``ExBudget``. Use `.unlimited` for tests and offline tools; use `.restricted` (or a budget loaded from live protocol parameters) for on-chain simulation.

```swift
// Offline / testing
var machine = CEKMachine(budget: .unlimited, costModel: .placeholder())

// On-chain simulation
let costModel = try CostModel.fromProtocolParams(try await context.protocolParameters())
var machine   = CEKMachine(budget: .restricted, costModel: costModel)
```

### Example

```swift
let source = "(program 1.0.0 [ [ (builtin addInteger) (con integer 3) ] (con integer 4) ])"
var parser = UPLCParser()
let named  = try parser.parse(source)
let ndb    = try DeBruijnConverter().convertToNamed(DeBruijnConverter().convert(named))

var machine = CEKMachine(budget: .unlimited, costModel: .placeholder())
let result  = try machine.run(ndb)
// result.term == .constant(.integer(7))
```

## Topics

### Running a program

- ``run(_:)``

### Budget and cost

- ``ExBudget``
- ``CostModel``
- ``MachineStepCosts``

### Errors

- ``MachineError``
