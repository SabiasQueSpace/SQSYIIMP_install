<div align="center">

# SQSYIIMP

### YiiMP Mining Pool Installation & Management Platform

**SabiasQue.Space**

[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04_LTS-E95420?logo=ubuntu&logoColor=white)](#supported-systems)
[![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnu-bash&logoColor=white)](#)
[![Release](https://img.shields.io/badge/Release-v1-blue)](#)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

**Automated YiiMP installation, Stratum management, daemon deployment and pool administration.**

</div>

---

## Quick Install

Run SQSYIIMP from a normal user account with sudo privileges:

~~~bash
curl -fsSL https://raw.githubusercontent.com/SabiasQueSpace/SQSYIIMP_install/main/install.sh | bash
~~~

Default installer directory:

~~~text
~/sqsyiimp
~~~

Main installer:

~~~text
~/sqsyiimp/install/start.sh
~~~

---

## What is SQSYIIMP?

SQSYIIMP provides an installation and management environment for YiiMP cryptocurrency mining pools.

The project includes tools for:

- YiiMP installation
- Database configuration
- NGINX and PHP setup
- SSL configuration
- Stratum installation
- Multi-Stratum management
- Cryptocurrency daemon building
- Remote Stratum servers
- WireGuard networking
- Pool service management
- YiiMP upgrades
- Health checks
- Server maintenance

---

## Main Commands

| Command | Description |
|---|---|
| `yiimpool` | Open the main SQSYIIMP management menu |
| `addport` | Interactive Stratum port manager |
| `addport --stratums` | List available Stratum binaries |
| `addport -s` | Short form for Stratum binary list |
| `addport --algos` | List available algorithms |
| `addport -a` | Short form for algorithm list |
| `screens start` | Start YiiMP service screens |
| `screens stop` | Stop YiiMP service screens |
| `screens restart` | Restart YiiMP service screens |
| `motd` | Display the SQSYIIMP system dashboard |

---

## Stratum Port Manager

Start the interactive manager:

~~~bash
addport
~~~

List installed Stratum binaries:

~~~bash
addport --stratums
~~~

or:

~~~bash
addport -s
~~~

List algorithms:

~~~bash
addport --algos
~~~

or:

~~~bash
addport -a
~~~

Configure a coin directly:

~~~bash
addport COIN ALGORITHM BINARY
~~~

Example:

~~~bash
addport GAEL kawpow stratum-kp
~~~

SQSYIIMP can bind a dedicated coin configuration to the selected Stratum executable.

---

## Service Management

Start all YiiMP service screens:

~~~bash
screens start
~~~

Stop them:

~~~bash
screens stop
~~~

Restart them:

~~~bash
screens restart
~~~

Common YiiMP screens include:

~~~text
main
loop2
blocks
debug
~~~

Attach to a screen:

~~~bash
yiimp-screens attach main
~~~

Detach without stopping it:

~~~text
Ctrl+A, D
~~~

Display the server dashboard:

~~~bash
motd
~~~

---

## YiiMP Source Selection

SQSYIIMP allows the operator to select the YiiMP source repository during installation.

| ID | YiiMP repository | Default |
|---:|---|:---:|
| 1 | `Kudaraidee/yiimp` | |
| 2 | `tpruvot/yiimp` | |
| 3 | `Afiniel-tech/yiimp` | |
| 4 | `afiniel/yiimp` | |
| 5 | `SabiasQueSpace/yiimp` | ✓ |
| 6 | `tpfuemp/yiimp` | |

The YiiMP source selector is independent from the SQSYIIMP installer repository.

Official SQSYIIMP repository:

~~~text
https://github.com/SabiasQueSpace/SQSYIIMP_install
~~~

---

## Repository Layout

~~~text
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
│   ├── start.sh
│   ├── requirements.sh
│   ├── conf/
│   └── utils/
│
├── stratum_manager/
│   ├── addport.sh
│   ├── runner.sh
│   ├── install.sh
│   └── install-runtime.sh
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
~~~

---

## Default Paths

| Component | Path |
|---|---|
| SQSYIIMP installer | `~/sqsyiimp` |
| YiiMP data | `/home/crypto-data/yiimp` |
| YiiMP website | `/home/crypto-data/yiimp/site` |
| Wallet data | `/home/crypto-data/wallets` |
| Stratum runtime | `/home/crypto-data/yiimp/site/stratum` |
| Stratum configs | `/home/crypto-data/yiimp/site/stratum/config` |

---

## Stratum Configuration

A dedicated configuration can select its runtime binary:

~~~ini
[RUNTIME]
binary = stratum-kp
~~~

Example configuration:

~~~text
/home/crypto-data/yiimp/site/stratum/config/gael.kawpow.conf
~~~

---

## Daemon Builder

The daemon builder is located under:

~~~text
daemon_builder/
~~~

It provides tools for downloading, compiling and deploying cryptocurrency wallet daemons used by the pool.

---

## Upgrade Environment

Upgrade tools are located under:

~~~text
yiimp_upgrade/
~~~

They provide utilities for:

- YiiMP updates
- Database maintenance
- Stratum configuration updates
- Restore operations
- Health checks

---

## Supported Systems

### Primary target

~~~text
Ubuntu Server 24.04 LTS
~~~

The installer also contains compatibility handling for Ubuntu 22.04 LTS.

Other operating systems or releases should be tested before production deployment.

---

## Security

Never commit server credentials or private material to this repository.

Examples:

~~~text
.env
*.pem
*.key
*.p12
*.pfx
*.log
*.pid
*.backup.*
*.bak.*
~~~

Never publish:

- Database passwords
- Wallet private keys
- RPC passwords
- Exchange API secrets
- SSH private keys
- WireGuard private keys

---

## Reporting Issues

Issue tracker:

~~~text
https://github.com/SabiasQueSpace/SQSYIIMP_install/issues
~~~

Useful information for a bug report:

- Operating system version
- SQSYIIMP version
- Installation step
- Relevant error output
- Stratum or service involved

Never include passwords, private keys or API secrets.

---

## Credits

SQSYIIMP includes ideas, structure, compatibility work, helper logic and inspiration from several open-source YiiMP installation projects and related server tooling.

Special thanks to:

- [Vaudois](https://github.com/vaudois/yiimp_install_scrypt)
- Afiniel
- [DirtyHarryDev](https://github.com/DirtyHarryDev/Yiimp-Server-Installer)
- [Mail-in-a-Box](https://github.com/mail-in-a-box/mailinabox) — base framework and helper functions
- [cryptopool-builders](https://github.com/cryptopool-builders/Multi-Pool-Installer) — original multi-pool installer
- [Kudaraidee/yiimp](https://github.com/Kudaraidee/yiimp) — YiiMP source code

SQSYIIMP is maintained and extended by **SabiasQue.Space**.

---

## License

SQSYIIMP is distributed under the terms contained in:

~~~text
LICENSE
~~~

---

<div align="center">

### SQSYIIMP v1

**YiiMP Mining Pool Platform**

**SabiasQue.Space**

</div>
