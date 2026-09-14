# Stratum Manager

SabiasQue.Space

This directory contains the Stratum runtime and dedicated-port management tools used by SQSYIIMP.

## Commands

The primary command is intentionally short:

```bash
addport
```

Interactive `addport` lists the available algorithm templates and the executable Stratum binaries found in:

```text
/home/crypto-data/yiimp/site/stratum
```

Useful shortcuts:

```bash
addport --stratums
addport --algos
addport GAEL kawpow stratum-kawpow
removecoin GAEL
```

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
removecoin COSA
```

Remove only the managed Stratum configuration/controller:

```bash
sudo removecoin COSA --apply
```

Remove the Stratum and a registered daemon/node:

```bash
sudo removecoin COSA --apply --purge-node --coin-name cosanta
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
the canonical daemon name, binaries, datadir and daemon config.

## Source files

- `addport.sh` — creates or updates a dedicated coin port/config and lets the operator select the Stratum binary.
- `removecoin.sh` — dry-runs or safely removes a managed coin Stratum, with optional node/backups/DB purge.
- `runner.sh` — reads `[RUNTIME] binary` and launches that executable.
- `install.sh` — installs or refreshes the manager and runtime.
- `install-runtime.sh` — installs the live runner in the Stratum directory.
