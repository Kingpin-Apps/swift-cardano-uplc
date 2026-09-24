# ``SwiftCardanoUPLC``

A Swift runtime for Cardano's Untyped Plutus Core (UPLC).

## Overview

`SwiftCardanoUPLC` provides a complete UPLC toolchain for the Cardano blockchain:

- **Parse** UPLC textual programs into an AST
- **Evaluate** programs using the CEK machine with the chain's real cost model
- **Encode / decode** programs in the on-chain flat binary format
- **Validate** Plutus scripts inside Cardano transactions (Phase-2 validation)

### Key types

| Group | Types |
|-------|-------|
| AST | ``Program``, ``Term``, ``UPLCConstant``, ``UPLCType``, ``Name``, ``DeBruijn``, ``NamedDeBruijn`` |
| Builtins | ``DefaultFunction`` |
| Flat encoding | ``FlatEncoder``, ``FlatDecoder`` |
| CEK machine | ``CEKMachine``, ``CostModel``, ``ExBudget``, ``EvalResult``, ``MachineError`` |
| De Bruijn | ``DeBruijnConverter`` |
| Parser | ``UPLCParser`` |
| Pretty-printer | ``PrettyPrinter`` |
| TX evaluation | ``PhaseTwo``, ``PhaseTwoResult``, ``ScriptContextBuilder`` |

### Quick start

```swift
import SwiftCardanoUPLC

// 1. Parse
var parser = UPLCParser()
let named = try parser.parse("""
  (program 1.0.0
    [ (lam x (addInteger x (con integer 1))) (con integer 41) ])
  """)

// 2. Convert to NamedDeBruijn for the machine
let db   = try DeBruijnConverter().convert(named)
let ndb  = try DeBruijnConverter().convertToNamed(db)

// 3. Evaluate
var machine = CEKMachine(budget: .unlimited, costModel: .placeholder())
let result  = try machine.run(ndb)
// result.term == .constant(.integer(42))
```

## Topics

### Parsing and Printing

- ``UPLCParser``
- ``UPLCParseError``
- ``PrettyPrinter``

### AST

- ``Program``
- ``Term``
- ``UPLCConstant``
- ``UPLCType``
- ``DefaultFunction``

### Variable Representation

- ``DeBruijnConverter``
- ``DeBruijnError``
- ``Name``
- ``DeBruijn``
- ``NamedDeBruijn``

### CEK Machine

- ``CEKMachine``
- ``EvalResult``
- ``MachineError``

### Cost Model

- ``CostModel``
- ``ExBudget``
- ``MachineStepCosts``
- ``BuiltinCost``
- ``LinearCost``
- ``PlutusVersion``

### Flat Encoding

- <doc:FlatEncoding>
- ``FlatEncoder``
- ``FlatDecoder``
- ``BitWriter``
- ``BitReader``
- ``FlatDecodingError``

### Transaction Validation

- ``PhaseTwo``
- ``PhaseTwoResult``
- ``RedeemerResult``
