# Mainnet transactions

`transactions.json` holds real mainnet transactions together with the execution
units they declare on chain. A transaction the ledger accepted declares the units
its scripts really used, so `MainnetExUnitsTests` can treat them as the answer.

`protocol-parameters.json` is a snapshot of mainnet's parameters, which is where
the cost models come from. Refresh it with
`cardano-cli query protocol-parameters --mainnet`; the units in `transactions.json`
were charged under the models in force when each transaction was submitted, so
replacing the snapshot with one from after a cost-model change will make older
transactions disagree. Add new transactions instead of re-pinning old ones.

## Adding a transaction

Everything needed is public, so no node is required.

1. Find a candidate — one with scripts, and ideally with a validity interval,
   reference scripts or inline datums:

   ```bash
   curl -s 'https://api.koios.rest/api/v1/blocks?limit=6&select=hash'
   # then /block_txs, then /tx_info with _inputs, _assets, _scripts and _bytecode
   ```

   **Ask for `_assets`.** Without it the inputs come back with empty asset lists,
   the values are wrong, and the scripts fail for a reason that has nothing to do
   with this library.

2. Take the transaction's CBOR from `/tx_cbor`.

3. Resolve every input *and* reference input into a UTxO — `[[txId, index],
   output]` in CBOR — keeping each one's value, inline datum and reference script.
   A script spending through a reference script has no script in the witness set
   at all, so a missing reference input looks like a missing script.

4. The declared units are in `tx_info`'s `plutus_contracts`, under
   `input.redeemer.unit`.

## Why not the offline oracle

`cardano-cli conway transaction calculate-plutus-script-cost offline` is what
`LedgerScriptContextTests` uses, and it is the better tool when it applies — it
reports the ledger's own context bytes. It cannot be used here: its UTxO JSON has
no way to express an **inline datum** on an input, and a transaction whose scripts
read one would fail for that reason alone. Its `online` mode reads the live UTxO
set, which no longer holds a spent input.
