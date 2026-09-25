# Changelog

All notable changes to SQSYIIMP are documented in this file.

## Unreleased

### Added

- Quantus QPoW managed Stratum integration with native `quantus` configuration, per-coin runtime selection, managed `screen` service environment and automatic QTC service generation.
- Quantus VarDiff defaults for QTC with native integer difficulty, including a 1,000,000,000 initial difficulty, 250,000,000 minimum and 50,000,000,000,000 maximum.
- Quantus bridge environment support for managed Stratum services using `QUANTUS_NODE_ADDR`, authentication token and TLS certificate pin files while leaving `QUANTUS_SHARE_DIFFICULTY` unset for VarDiff.

### Fixed

- Remove project-specific branding and disk-cache coupling from the generic SQSYIIMP installer; custom pool cache and panel integrations remain external to SQSYIIMP.

- Mark QTC as supporting `getinfo` compatibility in the Quantus YiiMP database migration.


### Added
- Add optional Stratum binary capability discovery using the public `--help`, `--version` and `--algos` interface; when valid, algorithm availability is restricted for that specific binary, while binaries without introspection remain unrestricted and no Stratum source code is inspected.
- Add a coin-neutral `sha3x.conf` algorithm template owned by SQSYIIMP; it is installed into `config/templates/` without inspecting or depending on Stratum source capabilities.

- Separate reusable Stratum algorithm templates into `site/stratum/config/templates/` while keeping dedicated coin configs in `site/stratum/config/`; `addport`, DaemonBuilder, installer, removal cleanup, health checks and fresh/remote Stratum setup now understand the new layout and migrate legacy one-part templates safely.
- Let the Ethash/Etchash DaemonBuilder wizard use an existing reward address or create a new encrypted Geth/Core-Geth pool wallet directly inside the coin datadir; the temporary password file is removed immediately and SQSYIIMP never stores the wallet password.
- Add a dedicated DaemonBuilder wizard for Geth/Core-Geth compatible Ethash/Etchash coins: existing or downloaded Linux binaries, optional genesis/network arguments, local-only JSON-RPC, pruned `gcmode=full` profile when supported, per-coin systemd service, RPC helper, managed metadata and automatic handoff to `addport`.
- Add independent coin-neutral `ethash.conf` and `etchash.conf` repository templates, rendered by the installer into the managed template directory without overwriting administrator configurations.
- Extend `removecoin --purge-node` to understand managed EVM nodes and remove their systemd unit, runner, RPC helper, binary and datadir without using Bitcoin-style `-conf/-daemon` shutdown arguments.
- Manage Ethash and Etchash through the generic algorithm-template workflow; CoinBuilder/DaemonBuilder can install and configure coin nodes and hand them to `addport`, which creates the dedicated per-coin Stratum configuration for a Stratum implementation maintained in an independent source repository.
- Preview the exact backup paths, per-path sizes, total count and total size selected by `removecoin --purge-backups` before confirmation; apply mode removes only those planned paths and protects automatic `removecoin-db` safety backups.

<!-- SQSYIIMP_ETHASH_ETCHASH_CHANGELOG -->
### Documentation

- Add normalized English documentation for Ethash / Etchash EVM coins.
- Document separate `ethash` and `etchash` algorithm handling.
- Document DaemonBuilder, wallet backup, RPC, database, addport and Stratum validation.
- Add troubleshooting for sync state, invalid algorithms, duplicate wallet sections, runtime replacement and schema differences.

## v1.0.5 - 2026-09-14

### Added

- Add a safe `removecoin` manager with dry-run by default, exact managed Stratum cleanup, autostart/UFW cleanup, optional daemon/datadir purge, optional backup purge, and conservative YiiMP DB removal that refuses to delete coins with dependent rows.
- Persist non-secret per-coin management metadata under `site/stratum/managed/` so Stratum Manager and DaemonBuilder can remove registered paths without broad wildcard deletion.
- Show live elapsed-time progress while stopping coin daemons, allow a longer clean shutdown window before TERM, and keep refusing destructive node removal while an exact daemon process is still alive.
- Add explicit `--purge-db-data` removal for dependent YiiMP rows with automatic SQL backup, non-zero balance protection and a second destructive confirmation.
- Add `--wallet-symbol` so Stratum include/exclude symbols can differ safely from the YiiMP DB ticker during removal.

### Fixed

- Separate the canonical coin name from the YiiMP coin symbol during daemon installation, so Stratum config files, launchers, logs and GNU Screen sessions use the ticker (for example `rtm`) instead of the full name (`raptoreum`).
- Correct the daemon-builder coin prompts so the canonical wallet/daemon name and the Stratum symbol are no longer conflated.
- Allow `runner.sh --resolve` to validate a generated Stratum configuration
  before its per-coin log is provisioned by `addport`.
- Prevent the missing-log diagnostic from being followed by the misleading
  `Generated config could not resolve its selected Stratum binary` error.
- Make `removecoin --check` print an apply command that preserves the requested purge options instead of always suggesting Stratum-only removal.
- Clean exact wallet `exclude = SYMBOL` lines on removal even when the dedicated Stratum config was already removed and the algorithm can no longer be resolved.

## v1.0.2 - 2026-09-01

### Added

- Persist each coin's complete Stratum console in `/var/log/stratum-<coin>.log`.
- Store each Stratum autostart log in `/var/log/stratum-<coin>-boot.log`.
- Rotate Stratum logs daily, retaining seven rotations with compression.
- Create and migrate per-coin log files with the configured runtime ownership.
- Force existing and new per-coin Screen sessions to run as the YiiMP runtime user.
- Preserve administrator access to Stratum logs through per-file ACLs.
- Keep updated launchers synchronized with the newly selected config and binary.

### Fixed

- Synchronize the active MOTD files during full SQSYIIMP upgrades.
- Validate MOTD scripts before installing them.
- Detect the correct Ubuntu or Debian MOTD source automatically.
- Abort the upgrade if MOTD synchronization fails.

## v1.0.1 - 2026-08-29

### Added

- Added a system health section to the SQSYIIMP MOTD dashboard.
- Added CPU load, memory, disk, inode, swap and temperature checks.
- Added colored `OK`, `WARNING` and `CRITICAL` health indicators.
- Added status monitoring for Nginx, PHP-FPM, MariaDB, Fail2ban, Cron and UFW.
- Added automatic PHP-FPM service version detection.
- Added Ubuntu and Debian support for the enhanced dashboard.
