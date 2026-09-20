# Stratum Manager

SabiasQue.Space

This directory contains the Stratum runtime and dedicated-port management tools used by SQSYIIMP.

## Commands

The primary command is intentionally short:

```bash
addport
```

Interactive `addport` reads algorithm templates from:

```text
/home/crypto-data/yiimp/site/stratum/config/templates
```

and lists executable Stratum binaries from:

```text
/home/crypto-data/yiimp/site/stratum
```

Useful shortcuts:

```bash
addport --stratums
addport --algos
addport GAEL kawpow stratum-kawpow
addport VBC ethash stratum-kp
addport ETC etchash stratum-kp
removecoin GAEL
```

SQSYIIMP keeps coin-neutral algorithm templates under `config/templates/`.
Dedicated per-coin configurations remain directly under `config/`. During upgrades,
legacy one-part templates such as `sha256d.conf`, `kawpow.conf`, `ethash.conf` and
`etchash.conf` are migrated into the template directory without moving files such
as `btc.sha256d.conf` or `vbc.ethash.conf`. SQSYIIMP also installs coin-neutral
`ethash.conf` and `etchash.conf` templates plus a dedicated `vbc.ethash.conf` when
they are not already present. Both inherit the configured
pool/SQL credentials from `.yiimp.conf`. The VBC config uses TCP port `6453`,
initial difficulty `0.1`, `diff_min = 0.05`, `diff_max = 8192`,
`max_ttf = 50000`, and `include = VBC`; the base template remains coin-neutral so
future Ethash/Etchash coins can be created safely with `addport`. `addport`
can also bootstrap the two base templates from the existing SQSYIIMP credentials
when they are missing. Existing administrator configurations are never overwritten.

Each dedicated coin config stores the selected runtime executable:

```ini
[RUNTIME]
binary = stratum-kawpow
```

Per-coin services use the historical and simple command format:

```bash
stratum.gael start
stratum.gael stop
stratum.gael restart
stratum.gael status
```

The older `sqs-stratum-port` and `sqs-stratum-<coin>` names remain as compatibility aliases for installations upgraded from v2.7.6-sqs2.

## Safe coin removal

`removecoin` is dry-run by default:

```bash
removecoin MYC
```

Remove only the managed Stratum configuration/controller:

```bash
sudo removecoin MYC --apply
```

Remove the Stratum and a registered daemon/node:

```bash
sudo removecoin MYC --apply --purge-node --coin-name mycoin
```

The node purge may remove the daemon datadir and wallet. Use `--keep-wallet`
to preserve the datadir. `--purge-backups` is separate: the plan lists every
exact matching path, each size, the total count and total size before confirmation,
and apply mode removes only those planned paths. Automatic DB safety backups under
`yiimp/backups/removecoin-db/` are protected. `--purge-db` remains conservative
and refuses to delete the YiiMP coin row while dependent database rows exist.
If the operator explicitly wants to remove those rows too, use
`--purge-db-data`: SQSYIIMP first creates an automatic SQL row backup under
`yiimp/backups/removecoin-db/`, refuses non-zero account/market balances, and
requires a second `PURGE SYMBOL` confirmation before deleting dependent rows.

When the Stratum wallet/include symbol differs from the YiiMP DB symbol, use
`--wallet-symbol` so exact `exclude = SYMBOL` lines are also cleaned safely.

Daemon shutdown is deliberately patient: the manager shows elapsed-time progress,
waits up to 120 seconds for a clean RPC-requested shutdown, then (only if needed)
sends TERM to the exact daemon PID and waits another 30 seconds. It never sends
SIGKILL automatically. The waits can be overridden with
`SQS_REMOVE_DAEMON_STOP_TIMEOUT` and `SQS_REMOVE_DAEMON_TERM_TIMEOUT`.

SQSYIIMP stores non-secret per-coin management metadata in
`site/stratum/managed/<coin>.conf`. DaemonBuilder augments the same file with
the canonical daemon name, binaries, datadir and daemon config. Geth/Core-Geth
compatible Ethash/Etchash nodes are registered as `NODE_TYPE=evm`, including
their systemd service, local JSON-RPC endpoint and P2P port so `removecoin
--purge-node` can remove them without applying Bitcoin-style daemon flags.

## Source files

- `addport.sh` — creates or updates a dedicated coin port/config and lets the operator select the Stratum binary.
- `removecoin.sh` — dry-runs or safely removes a managed coin Stratum, with optional node/backups/DB purge.
- `runner.sh` — reads `[RUNTIME] binary` and launches that executable.
- `install.sh` — installs or refreshes the manager, migrates legacy algorithm templates into `config/templates/`, and preserves dedicated coin configs in `config/`.
- `install-runtime.sh` — installs the live runner in the Stratum directory.

<!-- SQSYIIMP_ETHASH_ETCHASH_STRATUM_DOCS_START -->
## Ethash / Etchash

The shared Ethash-family runtime supports separate `ethash` and `etchash`
algorithm selections.

Check the Etchash source/runtime integration:

```bash
sudo bash stratum_manager/patches/etchash-etc/install.sh --check
```

If the source reports `patched`, no reinstall is required.

For a pristine supported source:

```bash
sudo bash stratum_manager/patches/etchash-etc/install.sh
```

Full node, database, addport, validation, and troubleshooting guide:

```text
docs/ETHASH-ETCHASH-MANUAL.md
```
<!-- SQSYIIMP_ETHASH_ETCHASH_STRATUM_DOCS_END -->


<!-- SQS_STRATUM_CAPABILITY_API_V1 -->

### Stratum capability discovery

SQSYIIMP keeps its own global algorithm catalogue and does not inspect
Stratum source code to determine supported algorithms.

A selected Stratum may optionally expose this public binary interface:

- `--help`
- `--version`
- `--algos`

When all three commands provide a valid interface, the algorithm list
returned by `--algos` is authoritative for that specific Stratum binary.

If the interface is unavailable, incomplete or invalid, the Stratum
capabilities are considered unknown and SQSYIIMP does not restrict its
algorithm catalogue.

Capabilities can be inspected with:

`addport --capabilities STRATUM_BINARY`

This capability detection uses only the executable public interface.
Stratum source files, repository layout and implementation details are
not inspected.
