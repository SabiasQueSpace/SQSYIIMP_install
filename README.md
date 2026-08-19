<div align="center">

# SQSYIIMP

### YiiMP Mining Pool Installation & Management Platform

**SabiasQue.Space**

[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04_LTS-E95420?logo=ubuntu&logoColor=white)](#supported-systems)
[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnu-bash&logoColor=white)](#)
[![Latest Tag](https://img.shields.io/github/v/tag/SabiasQueSpace/SQSYIIMP_install?sort=semver&label=release)](https://github.com/SabiasQueSpace/SQSYIIMP_install/tags)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

**Automated YiiMP installation, Stratum management, daemon deployment and mining pool administration.**

</div>

---

## Quick Install

Run SQSYIIMP from a normal Linux user account with `sudo` privileges:

```bash
curl -fsSL https://raw.githubusercontent.com/SabiasQueSpace/SQSYIIMP_install/main/install.sh | bash
```

Default installer directory:

```text
~/sqsyiimp
```

Main installer:

```text
~/sqsyiimp/install/start.sh
```

After installation, the main management interface can be launched with:

```bash
yiimpool
```

---

## What is SQSYIIMP?

**SQSYIIMP** is an installation, configuration and administration platform for
YiiMP cryptocurrency mining pools.

It provides tools for:

- YiiMP installation
- Database configuration
- NGINX configuration
- PHP configuration
- SSL setup
- Stratum installation
- Multiple Stratum binaries
- Stratum port management
- Cryptocurrency daemon building
- Wallet daemon deployment
- Remote Stratum servers
- WireGuard networking
- YiiMP screen management
- Pool service management
- SQSYIIMP upgrades
- YiiMP upgrades
- Health checks
- Backup and restore operations
- Server maintenance

SQSYIIMP is designed to keep the installation repository, active runtime
components and pool infrastructure clearly separated.

---

## Main Commands

| Command | Description |
|---|---|
| `yiimpool` | Open the main SQSYIIMP management menu |
| `daemonbuilder` | Open the cryptocurrency DaemonBuilder |
| `addport` | Open the interactive Stratum port manager |
| `addport --stratums` | List available Stratum binaries |
| `addport -s` | Short form for Stratum binary list |
| `addport --algos` | List available algorithms |
| `addport -a` | Short form for algorithm list |
| `addport --update` | Check and start a SQSYIIMP update |
| `addport -u` | Short form for SQSYIIMP update |
| `screens start` | Start all YiiMP service screens |
| `screens stop` | Stop all YiiMP service screens |
| `screens restart` | Restart all YiiMP service screens |
| `screens status` | Display YiiMP service screen status |
| `yiimp-screens status` | Display detailed YiiMP screen status |
| `yiimp-screens attach main` | Attach to the YiiMP main screen |
| `yiimp-screens restart loop2` | Restart an individual screen |
| `motd` | Display the SQSYIIMP server dashboard |

---

## SQSYIIMP Update System

SQSYIIMP uses a **unified update engine**.

A new SQSYIIMP release can be detected and started from:

```text
yiimpool
daemonbuilder
addport --update
```

All three interfaces use the same update system.

SQSYIIMP checks the public GitHub tags of the official repository to determine
the latest published release.

Official repository:

```text
https://github.com/SabiasQueSpace/SQSYIIMP_install
```

### Upgrade workflow

Before applying a full installer upgrade, SQSYIIMP performs several checks.

The upgrade process includes:

1. Detect the installed SQSYIIMP version.
2. Detect the latest published GitHub tag.
3. Verify system requirements.
4. Verify required services.
5. Verify the Git repository state.
6. Refuse to overwrite uncommitted local changes.
7. Create a system backup.
8. Fetch the published release.
9. Update the `main` branch without leaving the repository in detached HEAD.
10. Synchronize active SQSYIIMP runtime files.
11. Update the installed version metadata.
12. Verify services after the upgrade.

Installed version metadata is stored in:

```text
/etc/yiimpoolversion.conf
```

Example:

```text
VERSION=v1.0.0
```

### Local modification protection

If the SQSYIIMP repository contains uncommitted changes, a full automatic
upgrade is aborted.

This protects locally modified installer files from being overwritten.

Check repository status with:

```bash
cd ~/sqsyiimp
git status
```

Commit, preserve or restore local modifications before starting an upgrade.

---

## Stratum Port Manager

Start the interactive Stratum manager:

```bash
addport
```

List installed Stratum binaries:

```bash
addport --stratums
```

or:

```bash
addport -s
```

List available algorithms:

```bash
addport --algos
```

or:

```bash
addport -a
```

Configure a coin directly:

```bash
addport COIN ALGORITHM BINARY
```

Example:

```bash
addport GAEL kawpow stratum-kp
```

SQSYIIMP can bind an individual coin configuration to a selected Stratum
runtime executable.

Check for a new SQSYIIMP release from Addport:

```bash
addport --update
```

or:

```bash
addport -u
```

---

## Multiple Stratum Binaries

SQSYIIMP supports installations where different coins or algorithms use
different Stratum executables.

Examples may include:

```text
stratum
stratum-assic-ssl
stratum-kp
```

Available binaries can be displayed with:

```bash
addport --stratums
```

The Stratum manager keeps coin configuration separate from runtime binary
selection.

---

## Stratum Configuration

A dedicated coin configuration can select its runtime binary.

Example:

```ini
[RUNTIME]
binary = stratum-kp
```

Example configuration path:

```text
/home/crypto-data/yiimp/site/stratum/config/gael.kawpow.conf
```

This allows different Stratum implementations to coexist under the same YiiMP
installation.

---

## YiiMP Screen Management

SQSYIIMP provides a dedicated screen manager for YiiMP background processes.

The YiiMP screens run under the YiiMP data user rather than the administrator
login account.

Common screens are:

```text
main
loop2
blocks
debug
```

### Start all screens

```bash
screens start
```

### Stop all screens

```bash
screens stop
```

### Restart all screens

```bash
screens restart
```

### Display status

```bash
screens status
```

or:

```bash
yiimp-screens status
```

### Restart one screen

```bash
yiimp-screens restart loop2
```

Other examples:

```bash
yiimp-screens restart main
yiimp-screens restart blocks
yiimp-screens restart debug
```

### Attach to a screen

```bash
yiimp-screens attach main
```

Legacy interactive screen commands are also supported where configured:

```bash
screen -r main
screen -r loop2
screen -r blocks
screen -r debug
```

Detach without stopping the screen:

```text
Ctrl+A, D
```

The screen manager can also be controlled through systemd.

---

## SQSYIIMP Dashboard

Display the server dashboard:

```bash
motd
```

The dashboard can show information such as:

- SQSYIIMP version
- System load
- Disk usage
- Memory usage
- Network addresses
- YiiMP paths
- Screen status
- Server information

---

## Daemon Builder

The SQSYIIMP DaemonBuilder provides tools for downloading, compiling,
configuring and deploying cryptocurrency wallet daemons used by YiiMP.

Launch it with:

```bash
daemonbuilder
```

### Repository source

DaemonBuilder source files are maintained under:

```text
~/sqsyiimp/daemon_builder/utils/
```

### Installed runtime

The active DaemonBuilder runtime is normally installed under:

```text
/home/crypto-data/daemon_builder/
```

### Wallet data

Cryptocurrency wallet data is normally stored under:

```text
/home/crypto-data/wallets/
```

A typical daemon data directory may look like:

```text
/home/crypto-data/wallets/.coinname/
```

DaemonBuilder can assist with:

- Source compilation
- Precompiled daemon installation
- Wallet configuration
- RPC configuration
- Data directory creation
- Binary deployment
- Daemon startup
- YiiMP integration

When a newer SQSYIIMP release exists, DaemonBuilder can also offer access to
the unified SQSYIIMP updater.

---

## YiiMP Source Selection

SQSYIIMP allows the operator to select the YiiMP source repository during
installation.

| ID | YiiMP repository | Default |
|---:|---|:---:|
| 1 | `Kudaraidee/yiimp` | |
| 2 | `tpruvot/yiimp` | |
| 3 | `Afiniel-tech/yiimp` | |
| 4 | `afiniel/yiimp` | |
| 5 | `SabiasQueSpace/yiimp` | ✓ |
| 6 | `tpfuemp/yiimp` | |

The selected YiiMP source is independent from the SQSYIIMP installer
repository.

Official SQSYIIMP repository:

```text
https://github.com/SabiasQueSpace/SQSYIIMP_install
```

---

## Repository Layout

```text
SQSYIIMP_install/
├── install.sh
├── README.md
├── CHANGELOG.md
├── LICENSE
├── ver.sh
│
├── install/
│   ├── start.sh
│   ├── preflight.sh
│   ├── functions.sh
│   ├── questions_add_stratum.sh
│   └── yiimp_repositories.sh
│
├── daemon_builder/
│   └── utils/
│       ├── start.sh
│       ├── source.sh
│       ├── menu.sh
│       ├── menu2.sh
│       ├── menu3.sh
│       ├── upgrade.sh
│       └── conf/
│
├── stratum_manager/
│   ├── addport.sh
│   ├── runner.sh
│   ├── install.sh
│   └── install-runtime.sh
│
├── services/
│   ├── yiimp-screens.sh
│   ├── yiimp-screens.service
│   └── install-yiimp-screens.sh
│
├── yiimp_single/
│   ├── start.sh
│   ├── system.sh
│   ├── db.sh
│   ├── web.sh
│   ├── stratum.sh
│   ├── wireguard.sh
│   ├── nginx_confs/
│   └── yiimp_confs/
│
└── yiimp_upgrade/
    ├── start.sh
    ├── upgrade.sh
    ├── health_check.sh
    └── utils/
```

The exact contents of individual directories may evolve as SQSYIIMP develops.

---

## Default Paths

| Component | Path |
|---|---|
| SQSYIIMP installer | `~/sqsyiimp` |
| YiiMP data root | `/home/crypto-data/yiimp` |
| YiiMP website | `/home/crypto-data/yiimp/site` |
| YiiMP Stratum | `/home/crypto-data/yiimp/site/stratum` |
| Stratum configurations | `/home/crypto-data/yiimp/site/stratum/config` |
| Wallet data | `/home/crypto-data/wallets` |
| DaemonBuilder runtime | `/home/crypto-data/daemon_builder` |
| Installed version | `/etc/yiimpoolversion.conf` |
| SQSYIIMP functions | `/etc/functions.sh` |

Some paths may vary if a custom storage root is selected during installation.

---

## Upgrade Environment

Upgrade tools are maintained under:

```text
yiimp_upgrade/
```

They provide functionality for:

- SQSYIIMP release detection
- Full installer upgrades
- YiiMP upgrades
- Stratum upgrades
- System requirement checks
- Service validation
- Backup creation
- Restore operations
- Health checks
- Runtime synchronization

The update system is designed to avoid silently overwriting local repository
changes.

---

## Supported Systems

### Compatibility matrix

| Operating system | Status | Recommendation |
|---|---|---|
| **Ubuntu Server 24.04 LTS** | Primary supported platform | **Recommended** |
| **Ubuntu Server 22.04 LTS** | Compatibility handling included | Supported with compatibility considerations |
| Ubuntu releases other than 22.04 / 24.04 | Not officially validated | Test before production use |
| Debian and other Linux distributions | Not officially supported | Manual adaptation may be required |

### Ubuntu Server 24.04 LTS

Ubuntu Server **24.04 LTS** is the primary target for current SQSYIIMP
development and is the recommended operating system for new installations.

### Ubuntu Server 22.04 LTS

SQSYIIMP also contains compatibility handling intended for Ubuntu Server
**22.04 LTS**.

Package versions and some system components can differ from Ubuntu 24.04,
including:

- PHP and PHP-FPM
- MariaDB / MySQL
- OpenSSL
- Compilers
- Development libraries
- systemd services
- NGINX packages

Production operators should verify the complete installation and service state
after deployment.

### Other Ubuntu versions

Other Ubuntu releases should not automatically be considered fully compatible.

Before deploying another Ubuntu release in production, validate at minimum:

```text
NGINX
PHP-FPM
MariaDB / MySQL
YiiMP
Stratum
DaemonBuilder
systemd services
screen management
SSL
wallet daemons
```

Additional Ubuntu versions should only be marked as officially supported after
successful installation and runtime testing.

---

## Security

Never commit server credentials, private keys or other sensitive information
to the SQSYIIMP repository.

Examples of files or information that should not be published:

```text
.env
*.pem
*.key
*.p12
*.pfx
*.log
*.pid
*.backup.*
*.bak.*
```

Never publish:

- Database passwords
- Wallet private keys
- Wallet seeds
- RPC passwords
- Exchange API secrets
- SSH private keys
- WireGuard private keys
- SSL private keys
- Server authentication credentials

Before pushing changes:

```bash
git status
git diff
```

Review the complete change before committing it.

---

## Reporting Issues

Issue tracker:

```text
https://github.com/SabiasQueSpace/SQSYIIMP_install/issues
```

Useful information for a bug report includes:

- Ubuntu version
- SQSYIIMP version
- YiiMP source repository
- Installation step
- Relevant error output
- Stratum binary involved
- Algorithm involved
- Cryptocurrency daemon involved
- Service status

Never include:

- Passwords
- Wallet private keys
- Seeds
- RPC secrets
- API secrets
- SSH private keys

---

## Credits

SQSYIIMP includes ideas, compatibility work, structure, helper logic and
inspiration from several open-source YiiMP projects, installers and Linux
server management projects.

Special thanks and acknowledgement to:

- [Vaudois / yiimp_install_scrypt](https://github.com/vaudois/yiimp_install_scrypt)
- [Afiniel-tech](https://github.com/Afiniel-tech/) — YiiMP development, tooling and ecosystem contributions
- [DirtyHarryDev / Yiimp-Server-Installer](https://github.com/DirtyHarryDev/Yiimp-Server-Installer)
- [Mail-in-a-Box](https://github.com/mail-in-a-box/mailinabox) — server framework and helper-function inspiration
- [cryptopool-builders / Multi-Pool-Installer](https://github.com/cryptopool-builders/Multi-Pool-Installer) — multi-pool installer work
- [Kudaraidee/yiimp](https://github.com/Kudaraidee/yiimp) — YiiMP source code
- [tpruvot/yiimp](https://github.com/tpruvot/yiimp) — YiiMP development
- YiiMP developers and contributors
- Open-source cryptocurrency developers whose wallet daemons are supported by the platform

SQSYIIMP is maintained and extended by **SabiasQue.Space**.

---

## License

SQSYIIMP is distributed under the terms contained in:

```text
LICENSE
```

Review the license file before redistributing or modifying the project.

---

<div align="center">

### SQSYIIMP

**YiiMP Mining Pool Platform**

**SabiasQue.Space**

</div>