# RandomX / CryptoNote support in SQSYIIMP

SQSYIIMP_install is independent from Stratum source code and Stratum builds.
RandomX support in this repository covers the algorithm registration, configuration
template, and installation/configuration of RandomX/CryptoNote nodes and wallets.

## Components managed by SQSYIIMP_install

- Algorithm: `randomx`
- Default algorithm port: `4242`
- Template: `stratum_manager/templates/randomx.conf`
- SQL registration: `yiimp_single/yiimp_confs/2026-10-06-add-randomx.sql`
- DaemonBuilder mode: `Install RandomX / CryptoNote Coin Node`

## Stratum separation rule

SQSYIIMP_install does **not**:

- contain RandomX Stratum C/C++ source code;
- clone a Stratum source repository;
- compile a Stratum binary;
- install or replace a Stratum binary;
- patch Stratum C/C++ code.

Stratum source code and binaries are maintained independently. The template in
`stratum_manager/templates/randomx.conf` is configuration only.

## Install a RandomX / CryptoNote node and wallet

Run:

```bash
daemonbuilder
```

Choose:

`Install RandomX / CryptoNote Coin Node`

The wizard supports:

- an existing local daemon/wallet executable, or
- a precompiled Linux archive URL;
- dedicated daemon RPC and P2P ports;
- optional local encrypted wallet creation;
- a systemd node service;
- managed metadata for later administration/removal.

The wizard does not require or install a Stratum binary.

## Important

CryptoNote/Monero-family RPC is not Bitcoin Core RPC. Before enabling a coin for
production payouts, verify the coin-specific YiiMP RPC encoding, block template,
address validation, payout and wallet handling required by that network.
