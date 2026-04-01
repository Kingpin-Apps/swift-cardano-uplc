# ``SwiftCardanoUPLC/DeBruijnConverter``

Convert between the three program representations used in the UPLC lifecycle.

## Overview

UPLC programs flow through three representations:

| Type | Parameterisation | When used |
|------|-----------------|-----------|
| `Program<Name>` (`NamedProgram`) | Human-readable ``Name`` | Output of the parser; input to the pretty printer |
| `Program<DeBruijn>` (`DeBruijnProgram`) | ``DeBruijn`` indices | Input to the flat encoder |
| `Program<NamedDeBruijn>` (`NamedDeBruijnProgram`) | ``NamedDeBruijn`` (index + synthetic text) | Input to the CEK machine; output of the flat decoder |

`DeBruijnConverter` moves between these forms:

```
NamedProgram
    │  convert(_:)
    ▼
DeBruijnProgram ──── FlatEncoder ──── flat bytes
    │  convertToNamed(_:)                │
    ▼                          FlatDecoder
NamedDeBruijnProgram ◄──────────────────┘
    │  CEKMachine.run(_:)
    ▼
EvalResult
```

### Example

```swift
let converter = DeBruijnConverter()

// Named → DeBruijn (for encoding)
let db  = try converter.convert(namedProgram)

// DeBruijn → NamedDeBruijn (for evaluation)
let ndb = try converter.convertToNamed(db)

// NamedDeBruijn → DeBruijn (strip names after decoding)
let db2 = try converter.convertFromNamed(namedDeBruijnProgram)
```

## Topics

### Conversion

- ``convert(_:)``
- ``convertToNamed(_:)``
- ``convertFromNamed(_:)``

### Errors

- ``DeBruijnError``
