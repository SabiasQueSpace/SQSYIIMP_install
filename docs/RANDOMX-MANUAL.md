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

- existing local daemon/wallet executables;
- a precompiled Linux archive URL;
- cloning and compiling a CryptoNote source repository;
- an **external CryptoNote daemon with the wallet and Wallet RPC kept locally**;
- dedicated daemon RPC and P2P ports for local-node mode;
- optional local encrypted wallet creation;
- a systemd node service for local-node mode;
- a local Wallet RPC systemd service;
- managed metadata for later administration/removal.

### External daemon + local wallet

Choose `Use an external daemon + local wallet executables` when the blockchain
must not be stored on the YiiMP server. SQSYIIMP will:

- verify the remote daemon with `get_info`;
- avoid installing or creating a local daemon service;
- keep the wallet CLI, encrypted wallet file and Wallet RPC on the pool server;
- use wallet executables already installed locally or download a precompiled
  archive and install only the wallet CLI/Wallet RPC binaries;
- connect Wallet RPC to the external daemon with `--daemon-address`;
- store `NODE_MODE=remote`, the remote RPC host/port/URL and local Wallet RPC
  details in the managed metadata file;
- configure YiiMP `rpchost`/`rpcport` to use the external daemon;
- verify `get_block_template` using the pool reward address before completing
  the automatic YiiMP coin configuration.

The external RPC must be trusted and suitable for mining. A restricted public
RPC that answers `get_info` but blocks `get_block_template` is not sufficient.
This first remote-node implementation expects an HTTP daemon endpoint without
RPC authentication.

The wizard does not require or install a Stratum binary.

## Important

CryptoNote/Monero-family RPC is not Bitcoin Core RPC. Before enabling a coin for
production payouts, verify the coin-specific YiiMP RPC encoding, block template,
address validation, payout and wallet handling required by that network.
