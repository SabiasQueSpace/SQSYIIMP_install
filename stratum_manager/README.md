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

## Source files

- `addport.sh` — creates or updates a dedicated coin port/config and lets the operator select the Stratum binary.
- `runner.sh` — reads `[RUNTIME] binary` and launches that executable.
- `install.sh` — installs or refreshes the manager and runtime.
- `install-runtime.sh` — installs the live runner in the Stratum directory.
