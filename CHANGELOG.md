# Changelog

All notable changes to SQSYIIMP are documented in this file.

## Unreleased

### Added

- Persist each coin's complete Stratum console in `/var/log/stratum-<coin>.log`.
- Store each Stratum autostart log in `/var/log/stratum-<coin>-boot.log`.
- Rotate Stratum logs daily, retaining seven rotations with compression.
- Create and migrate per-coin log files with the configured runtime ownership.

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
