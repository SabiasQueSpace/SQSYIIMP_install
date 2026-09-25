# SQSYIIMP Stratum Etchash / ETC v1.0

Adds **Etchash (Ethereum Classic / ECIP-1099)** as a separate algorithm to the existing `stratum-kawpow-sqs` source while keeping the current **Ethash/VBC** path intact.

## Design

- `ethash` remains registered and continues to use `vbc_ethash_official_compute()`.
- `etchash` is registered separately.
- Etchash reuses the existing Ethereum miner/RPC/job plumbing by enabling `is_ethash`, and also sets a new `is_etchash` flag for consensus-specific PoW verification.
- ETC PoW verification uses a new bridge based on the already-vendored classic Ethash library. It does **not** modify VBC consensus constants and does **not** modify the KAWPOW copy of Ethash.
- ETC mainnet ECIP-1099 activation is fixed at block `11,700,000`.
- Before activation: 30,000-block epochs.
- From activation: cache/DAG size epoch uses 60,000 blocks while seed derivation continues on the old 30,000-block cadence, as required by ECIP-1099.
- For Etchash, the fourth `eth_getWork` value is not trusted as the work height. The Stratum resolves `pending`/`eth_blockNumber` through the daemon. This protects against Core-Geth returning an implausible fourth value while the node is syncing.

## Files changed

- `Makefile`
- `stratum.cpp`
- `stratum.h`
- `job.cpp`
- `ethash.cpp`
- new `etc_etchash_bridge.c`
- new `etc_etchash_bridge.h`

No `ethash -> etchash` rename is performed. Existing Ethash coins remain Ethash.

## Install

ETC Stratum must be stopped first.

```bash
cd /path/to/SQSYIIMP-Stratum-Etchash-ETC-v1.0
sudo bash install.sh --check
sudo bash install.sh
```

The installer checks the SHA-256 of the live source against the source snapshot supplied for this patch, creates a backup, builds `stratum`, deploys it as:

```text
/home/crypto-data/yiimp/site/stratum/stratum-ethash-test
```

and deliberately does **not** start ETC.

## Sync before mining

The ETC node supplied during development was still syncing. Do not enable miners until:

```bash
/usr/bin/ethereumclassic-rpc eth_syncing
```

returns JSON-RPC `result: false`.

Then:

```bash
/usr/bin/stratum.etc start
sleep 2
/usr/bin/stratum.etc status
tail -n 80 /var/log/stratum-etc.log
```

You should see:

```text
Algorithm engine selected: ETCHASH (Ethereum Classic ECIP-1099)
```

and no `ERROR: 13 invalid algo`.

## Optional bridge test

```bash
bash tests/test-bridge.sh
```

This builds the vendored VBC Ethash static library in a temporary directory and checks that the new ETC bridge is exactly compatible with classic Ethash before the ECIP-1099 fork using a known Ethash test vector.

## Rollback

The installer prints the backup directory it created. Restore it with:

```bash
sudo bash install.sh --rollback /home/crypto-data/yiimp/backups/stratum-etchash-YYYYMMDD-HHMMSS
```

## Validation performed while preparing this package

- new Etchash bridge compiles independently with `-Wall -Wextra -Werror` against the vendored VBC Ethash headers;
- known pre-fork Ethash vector final hash matched exactly;
- VBC and ETC bridge outputs matched exactly for the pre-fork vector;
- ECIP-1099 epoch/seed mapping was checked against the official specification and the reference `cpp-etchash` implementation.

A full Stratum link was not claimed from the preparation sandbox because its build environment does not match the pool server (notably missing server dependencies such as libsodium headers). The installer performs the authoritative full build on the target YiiMP server and automatically restores the original source/runtime if that build fails.

## v1.0.1 installer fix

This revision fixes two installer-only issues discovered during the first live deployment:

- Binary marker validation no longer uses `strings | grep -q` under `pipefail`, which could report a false negative because `strings` receives SIGPIPE after `grep -q` finds a match.
- Runtime deployment and rollback now use an atomic temporary-file + rename operation. This avoids `Text file busy` when another running Stratum (for example an existing Ethash/VBC instance) is still executing the shared runtime binary. Existing processes keep the old inode; new starts use the new binary.

The Etchash source patch itself is unchanged from v1.0.
