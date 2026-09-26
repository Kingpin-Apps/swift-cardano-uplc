# SwiftCardanoUPLC

A Swift implementation of the Cardano **Untyped Plutus Core (UPLC)** runtime. It provides:

- **Parser** — parse UPLC textual programs into an AST
- **Pretty Printer** — serialize an AST back to UPLC text
- **De Bruijn Converter** — convert between named and De Bruijn–indexed representations
- **CEK Machine** — evaluate UPLC programs under the chain's real cost model and execution budget
- **Flat Encoder / Decoder** — encode programs to / decode programs from the on-chain binary format
- **Phase-Two Validation** — evaluate all Plutus scripts in a Cardano transaction, PlutusV1 through V3

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

var machine = CEKMachine(budget: .unlimited, costModel: .placeholder())
let result = try machine.run(namedDB)

// result.term == .constant(.integer(42))
if case .constant(.integer(let n)) = result.term {
    print(n)   // 42
}
```

#### Execution budget

```swift
// Mainnet-equivalent restricted budget
var machine = CEKMachine(budget: .restricted, costModel: .placeholder())

// Custom budget
var machine = CEKMachine(
    budget: ExBudget(cpu: 10_000_000_000, mem: 14_000_000),
    costModel: .placeholder()
)
```

#### Failures, traces and observing a run

A failed run keeps what it produced: after `run` throws, `machine.logs`,
`machine.consumedBudget` and `machine.remainingBudget` describe the run up to
the failure. `evaluate` returns all of it without throwing:

```swift
let evaluation = machine.evaluate(program)
evaluation.succeeded      // false when the script failed
evaluation.logs           // trace messages, up to the failure
evaluation.consumedBudget // what it spent, even past the limit
```

Pass a `CEKObserver` to see each step — every term computed and value returned,
each builtin with its cost, each trace message and how the run ended. An
unobserved run costs nothing extra.

```swift
var recorder = CEKStepRecorder()
_ = try machine.run(program, observer: &recorder)
for step in recorder.steps { print(step.index, step.event, step.consumed) }
```

#### Cost model from protocol parameters

`.placeholder()` is not the chain's cost model — its budgets mean nothing, and it
reports ``isApproximate`` so callers can tell. For anything that matters, build the
real model from protocol parameters:

```swift
let params    = try await chainContext.protocolParameters()
let costModel = try CostModel.fromProtocolParams(params, version: .v3)
var machine   = CEKMachine(budget: .restricted, costModel: costModel)
```

A cost model belongs to one Plutus version. Protocol parameters carry each version's
model as a bare array of integers, tagged by position; the costing *shapes* come from
the Plutus release and differ between V1/V2 and V3 for a handful of builtins, so
costing a V3 script with the V2 model gives wrong budgets.

Older chains send shorter arrays that do not name the newest builtins' parameters.
Those builtins are left unpriced rather than the whole model being rejected, and a
script that somehow calls one is reported instead of running free.

The implementation is checked against the Plutus conformance suite's own expected
budgets — all 511 comparable cases are reproduced exactly.

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

let params   = try await chainContext.protocolParameters()
let phaseTwo = try PhaseTwo(protocolParameters: params)
let result   = try await phaseTwo.evaluate(
    transaction: tx,
    // Every input the transaction references, reference inputs included — a
    // script spending through a reference script has no script in its witness set.
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

All six redeemer purposes are evaluated: spending, minting, reward withdrawal,
certificate (`Publishing`), vote and proposal. The script context each one gets is
checked against the ledger's own, byte for byte — the fixtures under
`Tests/.../Resources/ledgercontext` hold contexts taken from a synced node, and
their README says how to make more.

A script sees a transaction's validity interval as POSIX milliseconds while the
transaction states it in slots, so pass a `SlotTimeline` — `.mainnet` and its
siblings cover the public networks, and `SlotTimeline(systemStart:eraHistory:)`
reads whatever a node reports. Without one, a transaction that has an interval is
refused rather than handed an unbounded one, which would quietly defeat every
deadline check the script makes.

PlutusV1, V2 and V3 all have their contexts checked against the ledger's, byte for
byte. V1 and V2 are not a smaller V3 — among other things their mint field always
carries a zero-ada entry, their withdrawals come in the opposite credential order,
and V1 holds its withdrawals and datums as lists of pairs rather than maps.

To run one redeemer's script yourself — observed, or again with a changed redeemer
or datum — `PhaseTwo.prepareScript(for:transaction:resolvedInputs:)` finds, decodes
and applies it, and `PhaseTwo.redeemers(of:)` lists a transaction's redeemers. Each
`RedeemerResult` carries `consumedBudget` and the traces of a failing script.

Real mainnet transactions are checked against the units they declare on chain, in
`MainnetExUnitsTests` — which is what caught V1 and V2 being priced by the wrong
builtin semantics variant.

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
│   ├── CostModel        — build the chain's cost model from protocol parameters
│   ├── CostingFunction  — the cost-function shapes a builtin can be priced by
│   ├── ExMemory         — how the cost model measures an argument's size
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
│   └── DefaultFunction  — built-in functions with arity and force counts
│
└── TX/
    ├── PhaseTwo         — transaction-level Phase-2 script evaluation
    ├── ScriptContext    — builds ScriptContext PlutusData for validators
    ├── CertificateData  — certificates as TxCert (V3) and DCert (V1/V2)
    └── GovernanceData   — voters, votes and proposal procedures as Data

PlutusV3's ScriptContext is a different structure from V1/V2 rather than an
extension of it: three top-level fields instead of two, sixteen TxInfo fields
instead of twelve, an integer fee, a raw transaction id, and a ScriptInfo
carrying the datum — which is why a V3 script takes a single argument.
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
