# Changelog

All notable changes to SQSYIIMP are documented in this file.

## Unreleased

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
