# SQSYIIMP — Ethash / Etchash Coin Installation Manual

This manual describes the operational procedure for installing, registering, validating, and troubleshooting EVM Proof-of-Work coins that use `ethash` or `etchash` with SQSYIIMP.

It assumes a current SQSYIIMP installation. Project updates, release tags, source patches, and upgrade procedures are intentionally outside the scope of this usage manual.

The instructions are generic. Replace example values with the values required by the target coin.

## 1. Ethash and Etchash are separate algorithms

Do not rename an existing `ethash` database row to `etchash`.

```text
╭──────────────────── ALGORITHM MODEL ─────────────────────╮
│ Standard Ethash-family coin      → algo = ethash         │
│ Ethereum Classic family          → algo = etchash        │
│ New or unfamiliar EVM coin       → verify PoW upstream   │
│ Existing Ethash coins            → keep ethash unchanged │
╰───────────────────────────────────────────────────────────╯
```

A coin being EVM-compatible does not prove that it uses Ethash or Etchash. Confirm the Proof-of-Work implementation before adding it.

---

## 2. Install the EVM node with DaemonBuilder

Start DaemonBuilder:

```bash
daemonbuilder
```

### Step 1 — Select the EVM installer

![DaemonBuilder menu](images/01-daemonbuilder-menu.png)

Choose **Install Ethash / Etchash EVM Coin Node**.

### Step 2 — Select the mining algorithm

![Mining algorithm](images/02-mining-algorithm.png)

Choose:

```text
ethash   → standard Ethash
etchash  → Ethereum Classic family
```

### Step 3 — Enter the full coin name

![Coin name](images/03-coin-name.png)

Example values in screenshots are illustrative only.

### Step 4 — Enter the YiiMP symbol

![Coin symbol](images/04-coin-symbol.png)

Use the exact ticker that will be stored in YiiMP.

### Step 5 — Enter the identifier

![Coin identifier](images/05-coin-identifier.png)

Use a stable lowercase identifier suitable for directories, services, and helper scripts.

Recommended format:

```text
letters and numbers only where practical
no spaces
no temporary version suffixes
```

### Step 6 — Choose how to provide the node binary

![Node binary source](images/06-node-binary-source.png)

Choose:

```text
local     → executable already exists on the server
download  → download a precompiled archive or executable
```

### Step 7 — Enter the download URL when required

![Precompiled node URL](images/07-precompiled-node-url.png)

Use a direct Linux archive or executable URL from the project's official release source.

### Step 8 — Enter the binary name

![Binary name](images/08-binary-name.png)

This is the executable expected inside the downloaded package, for example `geth`, `core-geth`, or another Geth-compatible client name.

### Step 9 — Set the JSON-RPC port

![JSON-RPC port](images/09-json-rpc-port.png)

This port is used locally by YiiMP and the Stratum.

### Step 10 — Set the P2P port

![P2P port](images/10-p2p-port.png)

This is the peer-to-peer TCP/UDP port used by the node.

### Step 11 — Set optional network arguments

![Network arguments](images/11-network-arguments.png)

Leave this field empty when the binary defaults to the correct network. Add the required network selector only when the client needs one.

Examples can include options such as:

```text
--classic
--networkid <id>
```

Do not copy a network flag from another coin without verifying it.

---

## 3. Reward wallet and backup policy

Choose whether to use an existing reward address or create a new encrypted wallet.

![Reward wallet](images/12-reward-wallet.png)

The pool configuration needs the **public `0x...` address**, not the private key or wallet password.

```text
╭──────────────────── WALLET SAFETY ──────────────────────╮
│ Back up the complete keystore directory                │
│ Back up the wallet password separately                 │
│ Do not place the wallet password in YiiMP RPC fields   │
│ Store recovery material outside the mining server      │
╰─────────────────────────────────────────────────────────╯
```

List accounts for a typical Geth-compatible client:

```bash
sudo -u crypto-data \
  /usr/bin/<IDENTIFIER>-geth \
  --datadir /home/crypto-data/wallets/.<IDENTIFIER> \
  account list
```

Adjust the executable name if the installed node uses a different suffix.

---

## 4. Synchronization and optional node settings

### Synchronization mode

![Synchronization mode](images/13-sync-mode.png)

Use `snap` when the client and network support it and a compact mining node is preferred. Use `full` when required by the network or client.

### Additional runtime arguments

![Additional arguments](images/14-additional-arguments.png)

Leave this empty unless the target coin explicitly requires additional flags.

### Optional genesis file or URL

![Genesis](images/15-genesis.png)

Leave this empty when the client has the network configuration built in. Supply a genesis only when the chain requires an external genesis file or URL.

### Start the node and enable it at boot

![Start node](images/16-start-node.png)

For a dedicated pool node, enabling the service at boot is normally appropriate.

---

## 5. Validate the node and RPC

The local JSON-RPC endpoint should normally bind to localhost:

```text
--http
--http.addr 127.0.0.1
--http.port <RPC_PORT>
--http.api eth,net,web3
```

Check listening ports:

```bash
sudo ss -lntp | grep ':<RPC_PORT>'
sudo ss -lntup | grep ':<P2P_PORT>'
```

Typical helper commands:

```bash
/usr/bin/<IDENTIFIER>-rpc eth_blockNumber
/usr/bin/<IDENTIFIER>-rpc eth_syncing
/usr/bin/<IDENTIFIER>-rpc net_peerCount
/usr/bin/<IDENTIFIER>-rpc eth_getWork
```

The node is ready for production mining only when `eth_syncing` returns:

```json
{"jsonrpc":"2.0","id":1,"result":false}
```

`eth_getWork` returning data while the node is still syncing is not sufficient to declare the node ready.

---

## 6. Register Ethash and Etchash separately in YiiMP

Set the database name:

```bash
DB="<YIIMP_DATABASE>"
```

Inspect the algorithm rows:

```bash
sudo mariadb "$DB" -e "
SELECT id,name,profit,rent,factor,overflow,norm,speedfactor,port,visible
FROM algos
WHERE name IN ('ethash','etchash')
ORDER BY name;
"
```

Never do this:

```sql
UPDATE algos SET name='etchash' WHERE name='ethash';
```

If `ethash` exists and `etchash` does not, create a separate Etchash row:

```bash
sudo mariadb "$DB" <<'SQL'
START TRANSACTION;

INSERT INTO algos
(
    name, profit, rent, factor, overflow, norm,
    color, speedfactor, port, visible, powlimit_bits
)
SELECT
    'etchash', 0, 0, factor, overflow, norm,
    color, speedfactor, port, visible, powlimit_bits
FROM algos
WHERE name='ethash'
  AND NOT EXISTS (
      SELECT 1 FROM algos WHERE name='etchash'
  )
LIMIT 1;

COMMIT;
SQL
```

Assign the intended algorithm only to the target coin:

```sql
UPDATE coins
SET algo='<ALGO>'
WHERE symbol='<SYMBOL>';
```

Verify:

```bash
sudo mariadb "$DB" -e "
SELECT id,symbol,name,algo
FROM coins
WHERE algo IN ('ethash','etchash')
ORDER BY algo,symbol;
"
```

If an example query fails because a column does not exist, inspect the live schema first:

```bash
sudo mariadb "$DB" -e "DESCRIBE coins; DESCRIBE algos;"
```

Do not assume every YiiMP fork has identical columns.

---

## 7. Configure the coin in the YiiMP administration panel

Use values that match the node that was actually installed.

```text
╭──────────────────── DAEMON / RPC ───────────────────────╮
│ Algorithm              <ALGO>                           │
│ Daemon program         /usr/bin/<node-binary>           │
│ Data/config folder     .<IDENTIFIER>                    │
│ Daemon OS user         crypto-data                      │
│ RPC host               127.0.0.1                        │
│ RPC port               <RPC_PORT>                       │
│ Dedicated Stratum      <STRATUM_PORT>                   │
│ RPC username           [empty when not required]        │
│ RPC password           [empty when not required]        │
│ Wallet account         0x...                            │
╰─────────────────────────────────────────────────────────╯
```

For a local Geth/Core-Geth-style HTTP endpoint without Basic authentication, leave the RPC username and password empty.

Do not use the keystore password as the RPC password.

---

## 8. Create the Stratum port with `addport`

Run:

```bash
/usr/bin/addport
```

A normalized Ethash/Etchash flow is:

```text
╭──────────────────────── ADDPORT FLOW ────────────────────────╮
│ 1. Select ethash or etchash                                  │
│ 2. Select the shared Ethash-family runtime                   │
│ 3. Configure NiceHash profile if required                    │
│ 4. Configure MiningRigRentals profile if required            │
│ 5. Choose automatic or manual dedicated Stratum port         │
│ 6. Generate the coin configuration                           │
│ 7. Start the managed Stratum only when the node is ready     │
╰───────────────────────────────────────────────────────────────╯
```

The current shared runtime can be:

```text
stratum-ethash-test
```

The generated configuration normally follows:

```text
/home/crypto-data/yiimp/site/stratum/config/<coin>.<algo>.conf
```

Example structure:

```ini
[TCP]
server = pool.example.org
port = <STRATUM_PORT>
password = <generated-secret>

[SQL]
host = localhost
database = <YIIMP_DATABASE>
username = <STRATUM_DB_USER>
password = <STRATUM_DB_PASSWORD>

[STRATUM]
algo = <ALGO>
difficulty = <initial-difficulty>
diff_min = <minimum>
diff_max = <maximum>
max_ttf = <target-time-to-find>

[WALLETS]
include = <SYMBOL>

[RUNTIME]
binary = stratum-ethash-test
```

Do not publish real SQL or TCP secrets from a production configuration.

### Marketplace difficulty profiles

If marketplace compatibility is needed, treat suggested values as starting profiles rather than permanent constants.

Example template:

```text
NiceHash: initial=2,   min=2,   max=2048
MRR:      initial=0.1, min=0.1, max=102.4
```

Adjust values after observing the actual miner, hashrate, share rate, rejects, and session behavior.

---

## 9. Validate the generated Stratum configuration

Inspect the file:

```bash
sudo cat "/home/crypto-data/yiimp/site/stratum/config/<coin>.<algo>.conf"
```

There should be only one `[WALLETS]` section:

```bash
grep -n '^\[WALLETS\]' \
  "/home/crypto-data/yiimp/site/stratum/config/<coin>.<algo>.conf"
```

Expected:

```ini
[WALLETS]
include = <SYMBOL>
```

Also confirm:

```text
algo = ethash    or    algo = etchash
runtime binary = shared Ethash-family runtime
coin symbol included in [WALLETS]
correct dedicated Stratum port
```

---

## 10. Start and validate the Stratum

Keep the Stratum stopped while the node is still syncing.

Once `eth_syncing` returns `false`:

```bash
/usr/bin/stratum.<coin> start
sleep 3
/usr/bin/stratum.<coin> status
sudo tail -n 100 /var/log/stratum-<coin>.log
```

Expected Ethash engine marker:

```text
Algorithm engine selected: ETHASH (...)
```

Expected Etchash engine marker:

```text
Algorithm engine selected: ETCHASH (...)
```

The log should not loop with:

```text
ERROR: 13 invalid algo
```

---

## 11. Troubleshooting

### `ERROR: 13 invalid algo`

The runtime does not recognize the configured algorithm.

Check the runtime:

```bash
strings /home/crypto-data/yiimp/site/stratum/stratum-ethash-test \
  | grep -E '^ethash$|^etchash$|Algorithm engine selected: (ETHASH|ETCHASH)'
```

Check all three algorithm references:

```text
coins.algo
[STRATUM] algo = ...
runtime engine support
```

They must agree. If the required engine marker is missing from the installed runtime, update SQSYIIMP through the normal project release/update mechanism before enabling the coin.

### `eth_syncing` returns an object

The node is still synchronizing. Keep the Stratum stopped.

### `eth_getWork` returns data while syncing

This does not prove that the node is production-ready. Wait until `eth_syncing` returns `false`.

### No peers

```bash
/usr/bin/<IDENTIFIER>-rpc net_peerCount
sudo ss -lntup | grep ':<P2P_PORT>'
sudo journalctl -u sqsyiimp-<IDENTIFIER>-node.service -n 100 --no-pager
```

### Duplicate `[WALLETS]` sections

```bash
grep -n '^\[WALLETS\]' \
  "/home/crypto-data/yiimp/site/stratum/config/<coin>.<algo>.conf"
```

Keep only one valid section.

### `Text file busy` when replacing a runtime binary

Do not manually overwrite an executable that is actively mapped by a running process. For manual maintenance, stop the relevant Stratum process first and use the normal SQSYIIMP update procedure for runtime changes.

```bash
/usr/bin/stratum.<coin> status
ps -ef | grep '[s]tratum-ethash-test'
```

### YiiMP RPC fields do not match a Geth-style node

For a local node without HTTP Basic authentication:

```text
RPC host      127.0.0.1
RPC port      node HTTP RPC port
RPC username  empty
RPC password  empty
Wallet        public 0x address
```

### SQL example fails because a column is missing

```bash
sudo mariadb "$DB" -e "DESCRIBE coins; DESCRIBE algos;"
```

### Minimum go-live test

```bash
/usr/bin/<IDENTIFIER>-rpc eth_syncing
/usr/bin/<IDENTIFIER>-rpc eth_getWork
/usr/bin/stratum.<coin> status
sudo tail -n 100 /var/log/stratum-<coin>.log
```

Expected state:

```text
eth_syncing = false
eth_getWork returns work
Stratum = RUNNING
correct engine marker is present
no invalid-algo loop
```

---

## 12. Ethereum Classic example

Ethereum Classic is a useful reference for an Etchash deployment:

```text
╭────────────────── ETHEREUM CLASSIC ─────────────────────╮
│ Identifier      ethereumclassic                         │
│ Algorithm       etchash                                 │
│ RPC             127.0.0.1:8545                         │
│ P2P             30303                                   │
│ Network args    --classic                               │
│ Sync mode       snap                                    │
╰─────────────────────────────────────────────────────────╯
```

Typical checks:

```bash
sudo systemctl status sqsyiimp-ethereumclassic-node.service --no-pager
/usr/bin/ethereumclassic-rpc eth_blockNumber
/usr/bin/ethereumclassic-rpc eth_syncing
/usr/bin/ethereumclassic-rpc net_peerCount
/usr/bin/ethereumclassic-rpc eth_getWork
/usr/bin/stratum.etc status
sudo tail -n 100 /var/log/stratum-etc.log
```

Do not reuse ETC-specific arguments for another coin unless its upstream documentation requires them.

---

## 13. Service lifecycle and removal

Status:

```bash
/usr/bin/stratum.<coin> status
```

Stop:

```bash
/usr/bin/stratum.<coin> stop
```

Restart:

```bash
/usr/bin/stratum.<coin> restart
```

Preview removal:

```bash
/usr/bin/removecoin <SYMBOL> --check --purge-node
```

Review the generated plan before performing the final removal.

---

## 14. Final checklist

```text
╭──────────────────────── FINAL CHECKLIST ────────────────────────╮
│ [ ] Upstream PoW algorithm verified                            │
│ [ ] Correct ethash / etchash selection                         │
│ [ ] Node service active                                       │
│ [ ] P2P port listening                                        │
│ [ ] Peers connected                                           │
│ [ ] JSON-RPC reachable on localhost                           │
│ [ ] eth_syncing returns false                                 │
│ [ ] Public reward address configured                          │
│ [ ] Keystore and password backed up safely                    │
│ [ ] coins.algo is correct                                     │
│ [ ] Existing Ethash coins still use ethash                    │
│ [ ] Etchash exists separately when required                   │
│ [ ] addport used the correct algorithm and runtime            │
│ [ ] Dedicated Stratum port configured                         │
│ [ ] Only one [WALLETS] section exists                         │
│ [ ] Runtime contains the required engine marker               │
│ [ ] Stratum log has no invalid-algo loop                      │
│ [ ] Real miner connection tested before public launch         │
╰─────────────────────────────────────────────────────────────────╯
```
