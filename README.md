# SwiftCardanoUPLC

A Swift implementation of the Cardano **Untyped Plutus Core (UPLC)** runtime. It provides:

- **Parser** — parse UPLC textual programs into an AST
- **Pretty Printer** — serialize an AST back to UPLC text
- **De Bruijn Converter** — convert between named and De Bruijn–indexed representations
- **CEK Machine** — evaluate UPLC programs with a configurable cost model and execution budget
- **Flat Encoder / Decoder** — encode programs to / decode programs from the on-chain binary format
- **Phase-Two Validation** — evaluate all Plutus scripts in a Cardano transaction

---

## Requirements

| Requirement | Version |
|-------------|---------|
| Swift | 6.0+ |
| macOS | 15+ |
| iOS | 17+ |

---

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Kingpin-Apps/swift-cardano-uplc.git", from: "0.1.0"),
],
targets: [
    .target(
        name: "MyTarget",
        dependencies: [
            .product(name: "SwiftCardanoUPLC", package: "swift-cardano-uplc"),
        ]
    ),
]
```

---

## Usage

### Parse a UPLC program

```swift
import SwiftCardanoUPLC

let source = """
(program 1.0.0
  (lam x x))
"""

var parser = UPLCParser()
let program = try parser.parse(source)  // NamedProgram
```

### Pretty-print a program

```swift
let printer = PrettyPrinter()
let text = printer.print(program)
print(text)
// (program 1.0.0
//   (lam x
//     x))
```

### Evaluate a program

The CEK machine evaluates `NamedDeBruijnProgram` — use `DeBruijnConverter` to prepare the program:

```swift
import SwiftCardanoUPLC

let source = """
(program 1.0.0
  [ (lam x (addInteger x (con integer 1))) (con integer 41) ])
"""

var parser = UPLCParser()
let named = try parser.parse(source)

// Convert to NamedDeBruijn (required by the CEK machine)
let namedDB = try DeBruijnConverter().convertToNamed(
    DeBruijnConverter().convert(named)
)

var machine = CEKMachine(budget: .unlimited, costModel: .defaultV2())
let result = try machine.run(namedDB)

// result.term == .constant(.integer(42))
if case .constant(.integer(let n)) = result.term {
    print(n)   // 42
}
```

#### Execution budget

```swift
// Mainnet-equivalent restricted budget
var machine = CEKMachine(budget: .restricted, costModel: .defaultV2())

// Custom budget
var machine = CEKMachine(
    budget: ExBudget(cpu: 10_000_000_000, mem: 14_000_000),
    costModel: .defaultV2()
)
```

#### Cost model from chain context

For production use, load the cost model from live protocol parameters:

```swift
let costModel = try await CostModel.fromChainContext(myChainContext)
var machine = CEKMachine(budget: .restricted, costModel: costModel)
```

### Flat encoding

The flat format is the on-chain binary encoding of UPLC programs.

```swift
// Encode
let db = try DeBruijnConverter().convert(named)
let flatBytes: Data = try FlatEncoder().encode(db)
let hex: String    = try FlatEncoder().encodeHex(db)

// Decode
let decoded: NamedDeBruijnProgram = try FlatDecoder().decode(flatBytes)
let decodedFromHex = try FlatDecoder().decodeHex(hex)
```

### Phase-Two transaction validation

`PhaseTwo` evaluates all Plutus scripts in a Cardano transaction concurrently:

```swift
import SwiftCardanoUPLC
import SwiftCardanoChain

let phaseTwo = PhaseTwo(chainContext: myChainContext)
let result = try await phaseTwo.evaluate(
    transaction: tx,
    resolvedInputs: resolvedUTxOs
)

if result.success {
    print("All scripts passed")
} else {
    for r in result.redeemers where !r.passed {
        print("Redeemer \(r.index) failed: \(r.error!)")
    }
}
```

---

## Architecture

```
SwiftCardanoUPLC
├── AST/
│   ├── Program          — versioned container for a UPLC program
│   ├── Term             — the UPLC grammar (var, lambda, apply, constant, …)
│   ├── UPLCConstant     — literal constant values (integer, bytestring, bool, …)
│   └── UPLCType         — constant type annotations
│
├── Parser/
│   └── UPLCParser       — parse UPLC textual syntax → NamedProgram
│
├── Pretty/
│   └── PrettyPrinter    — NamedProgram / NamedDeBruijnProgram → UPLC text
│
├── DeBruijn/
│   └── DeBruijnConverter — convert between Named ↔ DeBruijn ↔ NamedDeBruijn
│
├── Machine/
│   ├── CEKMachine       — evaluator (Control/Environment/Continuation)
│   ├── CostModel        — ExBudget, MachineStepCosts, per-builtin costs
│   ├── EvalResult       — final term + remaining budget + trace logs
│   └── MachineError     — evaluation failure cases
│
├── Flat/
│   ├── FlatEncoder      — DeBruijnProgram → flat bytes
│   ├── FlatDecoder      — flat bytes → NamedDeBruijnProgram
│   ├── BitWriter        — bit-level write buffer (MSB-first)
│   └── BitReader        — bit-level read buffer (MSB-first)
│
├── Builtins/
│   └── DefaultFunction  — 86 built-in functions with arity and force counts
│
└── TX/
    ├── PhaseTwo         — transaction-level Phase-2 script evaluation
    └── ScriptContext    — builds ScriptContext PlutusData for validators
```

### Program lifecycle

```
UPLC text
    │  UPLCParser.parse()
    ▼
NamedProgram (Program<Name>)
    │  DeBruijnConverter.convert()
    ▼
DeBruijnProgram (Program<DeBruijn>)
    │  FlatEncoder.encode()     FlatDecoder.decode()
    ▼                                   │
flat bytes ──────────────────────────── ▼
                             NamedDeBruijnProgram (Program<NamedDeBruijn>)
                                        │  CEKMachine.run()
                                        ▼
                                    EvalResult
```

---

## Built-in functions

UPLC ships with 86 built-in functions covering:

| Category | Examples |
|----------|---------|
| Integer arithmetic | `addInteger`, `subtractInteger`, `multiplyInteger`, `divideInteger`, `modInteger` |
| Comparison | `equalsInteger`, `lessThanInteger`, `lessThanEqualsInteger` |
| Byte strings | `appendByteString`, `sliceByteString`, `lengthOfByteString`, `indexByteString` |
| Strings | `appendString`, `equalsString`, `encodeUtf8`, `decodeUtf8` |
| Cryptography | `sha2_256`, `blake2b_256`, `blake2b_224`, `sha3_256`, `keccak_256`, `verifyEd25519Signature`, `verifyEcdsaSecp256k1Signature`, `verifySchnorrSecp256k1Signature` |
| BLS12-381 | `bls12_381_G1_add`, `bls12_381_G2_neg`, `bls12_381_millerLoop`, `bls12_381_finalVerify` |
| Plutus Data | `constrData`, `mapData`, `listData`, `iData`, `bData`, `unConstrData`, `equalsData` |
| Control | `ifThenElse`, `chooseList`, `trace` |
| Bitwise (V3) | `integerToByteString`, `byteStringToInteger`, `andByteString`, `orByteString`, `xorByteString` |

---

## Testing

The test suite includes:

- **Unit tests** — AST construction, bit I/O, De Bruijn conversion
- **Conformance tests** — all Plutus conformance test vectors for V2 and V3 (terms, constants, builtin semantics, interleaving, examples)
- **Integration tests** — flat encoding round-trips including byte-for-byte comparison against reference `.flat` fixtures

```bash
swift test
```

All 204 tests pass against the [Plutus conformance test suite](https://github.com/IntersectMBO/plutus/tree/master/plutus-conformance).

---

## License

See [LICENSE](LICENSE).
