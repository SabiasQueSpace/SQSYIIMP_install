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
`etchash.conf` are migrated into the template directory without moving dedicated
files such as `btc.sha256d.conf` or `vbc.ethash.conf`.

SQSYIIMP ships independent coin-neutral `ethash.conf` and `etchash.conf` templates.
The installer renders the configured pool/SQL credentials into missing runtime
templates without overwriting administrator-managed templates.

CoinBuilder/DaemonBuilder remains responsible for installing and configuring coin
nodes. When a coin is handed to `addport`, the Stratum manager uses the selected
algorithm template to create that coin's dedicated configuration and associate it
with a Stratum implementation maintained in an independent source repository.
SQSYIIMP does not bundle or maintain Stratum source code or project-specific
source patches. During installation or upgrade, SQSYIIMP may clone the configured
external Stratum repository and compile its source to produce the runtime binary.

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

SQSYIIMP manages `ethash` and `etchash` through coin-neutral configuration
templates and the external Stratum binary selected by the operator.

Stratum source code, compilation, patches and algorithm implementation are
maintained independently by the corresponding Stratum project and are not
bundled by SQSYIIMP.

Full node, database, addport, validation and troubleshooting guide:
docs/ETHASH-ETCHASH-MANUAL.md

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
