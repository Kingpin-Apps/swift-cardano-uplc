# Script context fixtures

Each `fixture-*.json` here holds a transaction, the UTxOs its inputs resolve to,
and the **exact CBOR of the script context the ledger built for it**. The tests
in `LedgerScriptContextTests` rebuild that context and compare it byte for byte.

The contexts are not hand-written. They come from `cardano-cli`, which reports
the arguments it handed a script when that script fails — so a validator that
returns `False` makes the node print the context it was given.

Matching execution units instead would be a much weaker check: the budget only
reflects the parts of the context a script actually looks at, so a field in the
wrong order, or missing outright, costs nothing and goes unnoticed. That is not
hypothetical — the redeemer map was in the wrong order and every budget still
matched.

## Regenerating a fixture

You need a synced node and the throwaway validator below. Nothing is submitted
and no funds are involved: the UTxOs are made up, and `offline` mode takes them
from a file.

1. An always-failing PlutusV3 validator, so the ledger reports its arguments:

   ```aiken
   validator dump {
     else(_ctx: Data) {
       False
     }
   }
   ```

   `aiken build && aiken blueprint convert > fail.plutus`

2. Snapshot the chain's parameters, once:

   ```bash
   cardano-cli query protocol-parameters --mainnet --out-file pparams.json
   cardano-cli query era-history --mainnet --out-file erahistory.json
   ```

3. Write a `utxo.json` in the shape `cardano-cli query utxo --output-json`
   produces, listing only the inputs the transaction spends, and build the
   transaction with `cardano-cli conway transaction build-raw`, witnessing
   whatever the fixture is about with `fail.plutus`.

4. Ask the ledger what context it builds:

   ```bash
   cardano-cli conway transaction calculate-plutus-script-cost offline \
     --genesis-file byron-genesis.json --era-history-file erahistory.json \
     --utxo-file utxo.json --protocol-params-file pparams.json \
     --tx-file tx.raw
   ```

   It fails, as intended, and prints `Script base64 encoded arguments:`. Decode
   that from base64 to get the context's CBOR; for PlutusV3 the whole blob is the
   single `ScriptContext` argument.

The error also names the redeemer it reported — `ScriptWitnessIndexCertificate 1`
and so on. It reports **one**, so a transaction with several script redeemers
tells you about only one of them: either give the transaction a single script
redeemer, or label the fixture with the one the error names.

## Fields

- `transaction` — the transaction's CBOR, as `build-raw` wrote it. Its bytes
  matter: the context carries the transaction's id, which is the hash of the body
  *as written*.
- `resolvedInputs` — each UTxO as CBOR, `[input, output]`.
- `redeemerTag` / `redeemerIndex` — which redeemer the context belongs to.
- `protocolMajorVersion` — a stake registration's deposit is hidden from the
  script at version 9 and visible from 10 on.
- `expectedContext` — the ledger's CBOR, hex-encoded.

## PlutusV1 and V2

Aiken only emits PlutusV3, so the V1 and V2 fixtures use a hand-built UPLC 1.0.0
program that always fails — `(program 1.0.0 (error))`, which flat-encodes to
`01000061` and goes in an envelope as `454401000061`. V3 uses UPLC 1.1.0, which V1
and V2 reject, so the Aiken script cannot stand in for them.

The ledger reports a V1 or V2 spending script's arguments as a CBOR **list** of
datum, redeemer and context, where a V3 script takes the context alone and the
ledger prints it bare. The fixtures store only the context — its last element.

A V1 or V2 fixture is worth writing for anything the two hold differently from V3,
which is more than it looks: the field count, the fee's shape, the mint's zero-ada
entry, whether withdrawals and datums are maps or lists of pairs, and the order
those come in.
