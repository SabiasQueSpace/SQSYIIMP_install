#!/usr/bin/env bash

############################################################
# SQSYIIMP
# Ethash / Etchash EVM node installer for DaemonBuilder
#
# Installs a Geth/Core-Geth compatible node for pool mining,
# creates a dedicated systemd service and then delegates the
# Stratum configuration to the managed addport workflow.
############################################################

set -euo pipefail

[[ -r /etc/daemonbuilder.sh ]] && source /etc/daemonbuilder.sh
[[ -r /etc/functions.sh ]] && source /etc/functions.sh
[[ -r /etc/yiimpool.conf ]] && source /etc/yiimpool.conf

STORAGE_USER="${STORAGE_USER:-crypto-data}"
STORAGE_GROUP="${STORAGE_GROUP:-${STORAGE_USER}}"
STORAGE_ROOT="${STORAGE_ROOT:-/home/${STORAGE_USER}}"
STRATUM_DIR="${PATH_STRATUM:-$STORAGE_ROOT/yiimp/site/stratum}"
MANAGED_DIR="$STRATUM_DIR/managed"
TMP_ROOT="${TMPDIR:-/tmp}"

# Fallback presentation helpers when this script is executed outside the
# normal DaemonBuilder shell environment.
if ! declare -F print_header >/dev/null 2>&1; then
    print_header()  { printf '\n=== %s ===\n\n' "$1"; }
    print_status()  { printf '[*] %s\n' "$1"; }
    print_error()   { printf 'ERROR: %s\n' "$1" >&2; }
    print_warning() { printf 'WARNING: %s\n' "$1" >&2; }
    print_success() { printf 'SUCCESS: %s\n' "$1"; }
    print_info()    { printf 'INFO: %s\n' "$1"; }
    print_divider() { printf '%s\n' '------------------------------------------------------------'; }
fi

fatal() {
    print_error "$1"
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || fatal "Required command not found: $1"
}

valid_id() {
    [[ "${1:-}" =~ ^[a-z0-9][a-z0-9_-]*$ ]]
}

valid_symbol() {
    [[ "${1:-}" =~ ^[A-Z0-9][A-Z0-9_-]*$ ]]
}

valid_port() {
    [[ "${1:-}" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
}

port_is_free_tcp() {
    local port="$1"
    ! ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)${port}$"
}

port_is_free_udp() {
    local port="$1"
    ! ss -lunH 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)${port}$"
}

find_free_tcp_port() {
    local start="${1:-8545}"
    local end="${2:-8999}"
    local port
    for ((port=start; port<=end; port++)); do
        if port_is_free_tcp "$port"; then
            printf '%s\n' "$port"
            return 0
        fi
    done
    return 1
}

find_free_p2p_port() {
    local start="${1:-30303}"
    local end="${2:-30999}"
    local port
    for ((port=start; port<=end; port++)); do
        if port_is_free_tcp "$port" && port_is_free_udp "$port"; then
            printf '%s\n' "$port"
            return 0
        fi
    done
    return 1
}

input_value() {
    local title="$1"
    local text="$2"
    local default_value="$3"
    local __var="$4"
    local value=""

    if command -v dialog >/dev/null 2>&1 && [[ -t 0 && -t 1 ]]; then
        value="$(dialog --stdout --backtitle 'SQSYIIMP' \
            --title "$title" --inputbox "$text" 18 82 "$default_value")" || exit 0
    else
        read -r -e -p "$text [$default_value]: " value
        value="${value:-$default_value}"
    fi

    printf -v "$__var" '%s' "$value"
}

input_secret() {
    local title="$1"
    local text="$2"
    local __var="$3"
    local value=""

    if command -v dialog >/dev/null 2>&1 && [[ -t 0 && -t 1 ]]; then
        value="$(dialog --stdout --backtitle 'SQSYIIMP' \
            --title "$title" --insecure --passwordbox "$text" 16 82)" || exit 0
    else
        read -r -s -p "$text: " value
        echo
    fi

    printf -v "$__var" '%s' "$value"
}

choose_menu() {
    local title="$1"
    local text="$2"
    local __var="$3"
    shift 3
    local value=""

    if command -v dialog >/dev/null 2>&1 && [[ -t 0 && -t 1 ]]; then
        value="$(dialog --stdout --backtitle 'SQSYIIMP' \
            --title "$title" --menu "$text" 18 78 8 "$@")" || exit 0
    else
        local -a values=()
        local -a labels=()
        while (($#)); do
            values+=("$1")
            labels+=("$2")
            shift 2
        done
        local i
        printf '%s\n' "$text"
        for i in "${!values[@]}"; do
            printf '  %d) %s\n' "$((i+1))" "${labels[$i]}"
        done
        read -r -p 'Selection: ' i
        [[ "$i" =~ ^[0-9]+$ ]] || fatal 'Invalid selection'
        (( i >= 1 && i <= ${#values[@]} )) || fatal 'Invalid selection'
        value="${values[$((i-1))]}"
    fi

    printf -v "$__var" '%s' "$value"
}

confirm_yesno() {
    local title="$1"
    local text="$2"

    if command -v dialog >/dev/null 2>&1 && [[ -t 0 && -t 1 ]]; then
        dialog --backtitle 'SQSYIIMP' --title "$title" --yesno "$text" 16 78
        return $?
    fi

    local answer=""
    read -r -p "$text [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

parse_shell_words() {
    local text="$1"
    python3 - "$text" <<'PY_PARSE'
import shlex
import sys
for item in shlex.split(sys.argv[1]):
    print(item)
PY_PARSE
}

shell_quote() {
    printf '%q' "$1"
}

binary_help=""
flag_supported() {
    local flag="$1"
    grep -Eq -- "(^|[[:space:]])${flag//./\\.}([=[:space:],]|$)" <<<"$binary_help"
}

download_or_copy_genesis() {
    local source="$1"
    local dest="$2"

    if [[ "$source" =~ ^https?:// ]]; then
        curl -fL --retry 3 --connect-timeout 15 "$source" -o "$dest"
    else
        [[ -f "$source" ]] || fatal "Genesis file not found: $source"
        cp -f "$source" "$dest"
    fi
}

extract_download() {
    local downloaded="$1"
    local destination="$2"

    mkdir -p "$destination"

    case "$downloaded" in
        *.tar.gz|*.tgz)
            tar -xzf "$downloaded" -C "$destination"
            ;;
        *.tar.xz|*.txz)
            tar -xJf "$downloaded" -C "$destination"
            ;;
        *.tar.zst|*.tzst)
            tar --zstd -xf "$downloaded" -C "$destination"
            ;;
        *.zip)
            unzip -q "$downloaded" -d "$destination"
            ;;
        *)
            # Direct executable download.
            cp -f "$downloaded" "$destination/$(basename "$downloaded")"
            ;;
    esac
}

write_runner() {
    local runner="$1"
    local installed_binary="$2"
    shift 2
    local arg

    sudo install -d -o root -g root -m 0755 /usr/local/lib/sqsyiimp

    {
        echo '#!/usr/bin/env bash'
        echo 'set -e'
        printf 'exec %q' "$installed_binary"
        for arg in "$@"; do
            printf ' %q' "$arg"
        done
        echo
    } | sudo tee "$runner" >/dev/null

    sudo chmod 0755 "$runner"
}

write_systemd_service() {
    local service_file="$1"
    local runner="$2"
    local description="$3"

    sudo tee "$service_file" >/dev/null <<EOF_SERVICE
[Unit]
Description=$description
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$STORAGE_USER
Group=$STORAGE_GROUP
ExecStart=$runner
Restart=on-failure
RestartSec=10
TimeoutStopSec=120
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF_SERVICE

    sudo chmod 0644 "$service_file"
    sudo systemctl daemon-reload
}

save_node_metadata() {
    local file="$1"
    local tmp
    tmp="$(mktemp)"

    sudo mkdir -p "$MANAGED_DIR"

    if [[ -r "$file" ]]; then
        grep -E '^(FORMAT|SYMBOL|WALLET_SYMBOL|ID|ALGO|PORT|STRATUM_BINARY|STRATUM_CONFIG|STRATUM_SERVICE|STRATUM_WRAPPER|STRATUM_LOG|STRATUM_BOOT_LOG)=' \
            "$file" > "$tmp" || true
    else
        cat > "$tmp" <<EOF_BASE
FORMAT=1
SYMBOL=$coin_symbol
WALLET_SYMBOL=$coin_symbol
ID=$coin_id
EOF_BASE
    fi

    # Avoid duplicate keys if a partially-created metadata file exists.
    grep -Ev '^(NODE_TYPE|COIN_NAME|DAEMON_BINARY|CLI_BINARY|TX_BINARY|UTIL_BINARY|HASH_BINARY|WALLET_BINARY|QT_BINARY|DAEMON_DATADIR|DAEMON_CONF|DAEMON_BOOT_LOG|DAEMON_SERVICE|DAEMON_SERVICE_FILE|DAEMON_RUNNER|DAEMON_RPC_PORT|DAEMON_RPC_URL|DAEMON_P2P_PORT|RPC_HELPER_BINARY)=' \
        "$tmp" > "${tmp}.clean" || true
    mv "${tmp}.clean" "$tmp"

    cat >> "$tmp" <<EOF_NODE
NODE_TYPE=evm
COIN_NAME=$coin_id
DAEMON_BINARY=$installed_name
CLI_BINARY=
TX_BINARY=
UTIL_BINARY=
HASH_BINARY=
WALLET_BINARY=
QT_BINARY=
DAEMON_DATADIR=$datadir
DAEMON_CONF=
DAEMON_BOOT_LOG=
DAEMON_SERVICE=$service_name
DAEMON_SERVICE_FILE=$service_file
DAEMON_RUNNER=$runner
DAEMON_RPC_PORT=$rpc_port
DAEMON_RPC_URL=http://127.0.0.1:$rpc_port
DAEMON_P2P_PORT=$p2p_port
RPC_HELPER_BINARY=$rpc_helper_name
EOF_NODE

    sudo install -o root -g root -m 0644 "$tmp" "$file"
    rm -f "$tmp"
}

install_rpc_helper() {
    local path="$1"
    sudo tee "$path" >/dev/null <<EOF_RPC
#!/usr/bin/env bash
set -euo pipefail
METHOD="\${1:-eth_blockNumber}"
PARAMS="\${2:-[]}"
curl -fsS -H 'Content-Type: application/json' \\
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"\${METHOD}\",\"params\":\${PARAMS},\"id\":1}" \\
  "http://127.0.0.1:$rpc_port"
echo
EOF_RPC
    sudo chmod 0755 "$path"
}

need_cmd python3
need_cmd ss
need_cmd curl
need_cmd systemctl

[[ "$EUID" -ne 0 ]] || fatal 'Run daemonbuilder as a regular administrative user, not root.'
id "$STORAGE_USER" >/dev/null 2>&1 || fatal "Storage user does not exist: $STORAGE_USER"

clear 2>/dev/null || true
print_header 'Ethash / Etchash EVM Coin Installation'
print_info 'This flow is for Geth/Core-Geth compatible PoW nodes used by the pool.'
print_info 'It installs a pruned/full node, local JSON-RPC and a dedicated Stratum config.'

evm_algo=''
choose_menu 'Mining Algorithm' 'Select the PoW family used by the coin.' evm_algo \
    ethash  'Ethash' \
    etchash 'Etchash (Ethereum Classic family)'

coin_name=''
input_value 'Coin Name' 'Full coin name (example: Ethereum Classic)' '' coin_name
[[ -n "${coin_name// }" ]] || fatal 'Coin name cannot be empty'

coin_symbol=''
input_value 'Coin Symbol' 'YiiMP ticker/symbol (example: ETC)' '' coin_symbol
coin_symbol="${coin_symbol^^}"
valid_symbol "$coin_symbol" || fatal "Invalid coin symbol: $coin_symbol"

coin_id="$(printf '%s' "$coin_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]//g')"
input_value 'Coin Identifier' 'Filesystem/service identifier' "$coin_id" coin_id
coin_id="${coin_id,,}"
valid_id "$coin_id" || fatal "Invalid coin identifier: $coin_id"

install_mode=''
choose_menu 'Node Binary' 'Choose how to provide the Geth-compatible node executable.' install_mode \
    local    'Use an existing local executable' \
    download 'Download a precompiled archive or executable'

mkdir -p "$TMP_ROOT"
tmpdir="$(mktemp -d "$TMP_ROOT/ethash-${coin_id}.XXXXXX")"
cleanup() {
    rm -rf "$tmpdir" 2>/dev/null || true
}
trap cleanup EXIT

source_binary=''
expected_binary='geth'

if [[ "$install_mode" == 'local' ]]; then
    input_value 'Existing Binary' 'Absolute path to the Geth/Core-Geth compatible executable' '/usr/bin/geth' source_binary
    [[ -x "$source_binary" ]] || fatal "Executable not found: $source_binary"
    expected_binary="$(basename "$source_binary")"
else
    download_url=''
    input_value 'Precompiled Node' 'Direct URL to a Linux archive (.tar.gz/.tar.xz/.zip) or executable' '' download_url
    [[ "$download_url" =~ ^https?:// ]] || fatal 'A valid http/https URL is required'

    input_value 'Binary Name' 'Executable name expected inside the archive (example: geth, core-geth, gvbc)' 'geth' expected_binary
    [[ "$expected_binary" =~ ^[A-Za-z0-9._-]+$ ]] || fatal 'Unsafe binary name'

    download_file="$tmpdir/$(basename "${download_url%%\?*}")"
    [[ -n "${download_file##*/}" ]] || download_file="$tmpdir/node-download"

    print_status 'Downloading node package...'
    curl -fL --retry 3 --connect-timeout 15 "$download_url" -o "$download_file"

    extract_dir="$tmpdir/extracted"
    extract_download "$download_file" "$extract_dir"

    source_binary="$(find "$extract_dir" -type f -name "$expected_binary" -perm -u+x -print -quit 2>/dev/null || true)"
    if [[ -z "$source_binary" ]]; then
        source_binary="$(find "$extract_dir" -type f -name "$expected_binary" -print -quit 2>/dev/null || true)"
    fi
    [[ -n "$source_binary" && -f "$source_binary" ]] || fatal "Could not find '$expected_binary' in the downloaded package"
    chmod +x "$source_binary"
fi

installed_name="${coin_id}-${expected_binary}"
installed_name="$(printf '%s' "$installed_name" | tr -cd 'A-Za-z0-9._-')"
installed_binary="/usr/bin/$installed_name"

print_status "Installing node binary as $installed_binary..."
sudo install -o root -g root -m 0755 "$source_binary" "$installed_binary"

binary_help="$($installed_binary --help 2>&1 || true)"
[[ -n "$binary_help" ]] || print_warning 'The node did not return --help output; generic Geth flags will be used.'

rpc_port="$(find_free_tcp_port 8545 8999 || true)"
[[ -n "$rpc_port" ]] || fatal 'No free JSON-RPC port found between 8545 and 8999'
input_value 'JSON-RPC Port' 'Local RPC port used by YiiMP/Stratum' "$rpc_port" rpc_port
valid_port "$rpc_port" || fatal "Invalid RPC port: $rpc_port"
port_is_free_tcp "$rpc_port" || fatal "RPC port is already in use: $rpc_port"

p2p_port="$(find_free_p2p_port 30303 30999 || true)"
[[ -n "$p2p_port" ]] || fatal 'No free P2P port found between 30303 and 30999'
input_value 'P2P Port' 'Peer-to-peer TCP/UDP port for this node' "$p2p_port" p2p_port
valid_port "$p2p_port" || fatal "Invalid P2P port: $p2p_port"
port_is_free_tcp "$p2p_port" && port_is_free_udp "$p2p_port" || fatal "P2P port is already in use: $p2p_port"

network_args_text=''
input_value 'Network Arguments' 'Optional network selector/client flags (examples: --classic or --networkid 61). Leave empty when the binary defaults to the correct chain.' '' network_args_text

# Create the coin datadir before selecting the reward address so DaemonBuilder
# can create a dedicated encrypted Geth/Core-Geth account when the operator
# does not already have a pool payout address.
datadir="$STORAGE_ROOT/wallets/.${coin_id}"
sudo install -d -o "$STORAGE_USER" -g "$STORAGE_GROUP" -m 0750 "$STORAGE_ROOT/wallets" "$datadir"

wallet_mode=''
choose_menu 'Pool Reward Wallet' 'Choose the address that will receive block rewards from this pool.' wallet_mode \
    existing 'Use an existing 0x reward address' \
    create   'Create a new encrypted wallet in this coin datadir'

etherbase=''
generated_wallet=false
generated_keyfile=''

if [[ "$wallet_mode" == 'existing' ]]; then
    input_value 'Pool Reward Address' 'Existing 0x mining reward/coinbase address used to build Ethash/Etchash work for the pool' '' etherbase
    [[ "$etherbase" =~ ^0x[0-9A-Fa-f]{40}$ ]] || fatal 'A valid 0x-prefixed 20-byte reward address is required for pool mining'
else
    # The password exists only in shell memory and in a short-lived 0600 file
    # required by geth account new. It is never stored in the service runner,
    # metadata or command line. The operator must remember/store it securely.
    wallet_password=''
    wallet_password_confirm=''
    input_secret 'New Pool Wallet' 'Password for the new encrypted pool wallet (do not forget it)' wallet_password
    [[ -n "$wallet_password" ]] || fatal 'Wallet password cannot be empty'
    input_secret 'Confirm Wallet Password' 'Repeat the new pool wallet password' wallet_password_confirm
    [[ "$wallet_password" == "$wallet_password_confirm" ]] || fatal 'Wallet passwords do not match'

    wallet_passfile="$(sudo -u "$STORAGE_USER" mktemp "/tmp/sqsyiimp-${coin_id}-wallet-pass.XXXXXX")"
    sudo -u "$STORAGE_USER" chmod 0600 "$wallet_passfile"
    printf '%s\n' "$wallet_password" | sudo -u "$STORAGE_USER" tee "$wallet_passfile" >/dev/null

    print_status "Creating encrypted pool wallet in $datadir..."
    account_output=''
    if ! account_output="$(sudo -u "$STORAGE_USER" "$installed_binary" \
        --datadir "$datadir" account new --password "$wallet_passfile" 2>&1)"; then
        sudo rm -f "$wallet_passfile"
        wallet_password=''
        wallet_password_confirm=''
        print_error 'The node client could not create the pool wallet.'
        printf '%s\n' "$account_output" >&2
        fatal "Wallet creation failed. Check that '$expected_binary' supports 'account new'."
    fi

    sudo rm -f "$wallet_passfile"
    wallet_password=''
    wallet_password_confirm=''

    etherbase="$(grep -Eo '0x[0-9A-Fa-f]{40}' <<<"$account_output" | tail -n1 || true)"
    generated_keyfile="$(find "$datadir/keystore" -maxdepth 1 -type f -name 'UTC--*' \
        -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2- || true)"

    # Fallback for clients whose account-new output does not print 0x... but
    # created a standard V3 keystore file.
    if [[ ! "$etherbase" =~ ^0x[0-9A-Fa-f]{40}$ && -n "$generated_keyfile" ]]; then
        key_address="$(python3 - "$generated_keyfile" <<'PY_WALLET'
import json
import sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as fh:
        address = json.load(fh).get('address', '')
except Exception:
    address = ''
if len(address) == 40 and all(c in '0123456789abcdefABCDEF' for c in address):
    print('0x' + address)
PY_WALLET
)"
        etherbase="$key_address"
    fi

    [[ "$etherbase" =~ ^0x[0-9A-Fa-f]{40}$ ]] || fatal 'Wallet was created but its 0x address could not be detected automatically'
    generated_wallet=true

    print_success "New pool reward wallet created: $etherbase"
    [[ -n "$generated_keyfile" ]] && print_info "Keystore file : $generated_keyfile"
    print_warning 'Back up the keystore file and remember the wallet password. Both are required to spend the rewards.'
fi

sync_mode='full'
if grep -qi -- 'snap' <<<"$binary_help"; then
    choose_menu 'Synchronization' 'Choose the synchronization mode. Pruning is enabled separately when supported.' sync_mode \
        snap 'Snap sync - preferred for a compact mining node' \
        full 'Full sync - use when the network does not support snap'
else
    print_info 'This client does not advertise snap sync; using full synchronization.'
fi

extra_args_text=''
input_value 'Additional Node Arguments' 'Optional extra runtime flags. Leave empty unless this coin requires them.' '' extra_args_text

# Build the runtime argument array. Modern Geth HTTP flags are preferred;
# legacy --rpc flags are used when the client exposes only the old interface.
declare -a runtime_args=()
runtime_args+=(--datadir "$datadir")

if flag_supported '--http' || flag_supported '--http.port'; then
    runtime_args+=(--http --http.addr 127.0.0.1 --http.port "$rpc_port" --http.api eth,net,web3)
elif flag_supported '--rpc' || flag_supported '--rpcport'; then
    runtime_args+=(--rpc --rpcaddr 127.0.0.1 --rpcport "$rpc_port" --rpcapi eth,net,web3)
else
    print_warning 'Could not detect modern or legacy JSON-RPC flags in --help output.'
    print_warning 'Using modern Geth --http flags because the pool requires local JSON-RPC.'
    runtime_args+=(--http --http.addr 127.0.0.1 --http.port "$rpc_port" --http.api eth,net,web3)
fi

if flag_supported '--port'; then
    runtime_args+=(--port "$p2p_port")
fi

if flag_supported '--syncmode'; then
    runtime_args+=(--syncmode "$sync_mode")
fi

# Geth/Core-Geth gcmode=full keeps the current state while garbage-collecting
# old state. This is the appropriate default for a pool node; archive mode is
# intentionally never enabled by this wizard.
if flag_supported '--gcmode'; then
    runtime_args+=(--gcmode full)
fi

# Geth/Core-Geth must have mining enabled to continuously build remote work.
# With miner threads set to zero, the node prepares work for the pool without
# wasting CPU on local Ethash/Etchash sealing.
if flag_supported '--mine'; then
    runtime_args+=(--mine)

    if flag_supported '--miner.etherbase'; then
        runtime_args+=(--miner.etherbase "$etherbase")
    elif flag_supported '--etherbase'; then
        runtime_args+=(--etherbase "$etherbase")
    else
        fatal 'The client supports --mine but no supported etherbase flag was detected'
    fi

    if flag_supported '--miner.threads'; then
        runtime_args+=(--miner.threads 0)
    elif flag_supported '--minerthreads'; then
        runtime_args+=(--minerthreads 0)
    fi
else
    print_warning 'The client does not advertise --mine. Verify that it serves eth_getWork/eth_submitWork for remote miners.'
fi

if flag_supported '--http.vhosts'; then
    runtime_args+=(--http.vhosts localhost,127.0.0.1)
fi

mapfile -t network_args < <(parse_shell_words "$network_args_text")
mapfile -t extra_args < <(parse_shell_words "$extra_args_text")
runtime_args+=("${network_args[@]}")
runtime_args+=("${extra_args[@]}")

genesis_source=''
input_value 'Genesis (optional)' 'Optional genesis.json path or URL. Leave empty for clients with a built-in network such as Core-Geth --classic.' '' genesis_source

if [[ -n "$genesis_source" ]]; then
    genesis_file="$datadir/genesis.json"
    print_status 'Installing genesis file...'
    download_or_copy_genesis "$genesis_source" "$genesis_file"
    sudo chown "$STORAGE_USER:$STORAGE_GROUP" "$genesis_file"
    sudo chmod 0640 "$genesis_file"

    declare -a init_args=(--datadir "$datadir")
    init_args+=("${network_args[@]}")
    init_args+=(init "$genesis_file")

    print_status 'Initializing chain database from genesis...'
    sudo -u "$STORAGE_USER" "$installed_binary" "${init_args[@]}"
fi

runner="/usr/local/lib/sqsyiimp/${coin_id}-evm-node"
service_name="sqsyiimp-${coin_id}-node.service"
service_file="/etc/systemd/system/$service_name"

write_runner "$runner" "$installed_binary" "${runtime_args[@]}"
write_systemd_service "$service_file" "$runner" "SQSYIIMP ${coin_name} Ethash/Etchash node"

rpc_helper_name="${coin_id}-rpc"
rpc_helper="/usr/bin/$rpc_helper_name"
install_rpc_helper "$rpc_helper"

print_divider
print_header 'Node Configuration'
print_info "Coin         : $coin_name ($coin_symbol)"
print_info "Algorithm    : $evm_algo"
print_info "Binary       : $installed_binary"
print_info "Datadir      : $datadir"
print_info "Service      : $service_name"
print_info "JSON-RPC     : http://127.0.0.1:$rpc_port"
print_info "P2P port     : $p2p_port"
print_info "Reward addr  : $etherbase"
if [[ "$generated_wallet" == true ]]; then
    print_info "Wallet       : newly created encrypted account"
    [[ -n "$generated_keyfile" ]] && print_info "Keystore     : $generated_keyfile"
fi
print_info "RPC helper   : $rpc_helper"

start_node=true
if ! confirm_yesno 'Start EVM Node' "Start the ${coin_name} node now and enable it at boot?"; then
    start_node=false
fi

if [[ "$start_node" == true ]]; then
    print_status "Enabling and starting $service_name..."
    sudo systemctl enable --now "$service_name"
    sleep 2

    if sudo systemctl is-active --quiet "$service_name"; then
        print_success 'EVM node service is running'
    else
        print_warning 'The EVM node service did not remain active.'
        print_info "Inspect it with: sudo journalctl -u $service_name -n 100 --no-pager"
    fi
fi

# Seed daemon metadata before addport. The patched addport preserves these EVM
# fields while adding Stratum metadata.
metadata_file="$MANAGED_DIR/${coin_symbol,,}.conf"
save_node_metadata "$metadata_file"

print_divider
print_header 'Creating Dedicated Stratum'

ADDPORT_BIN=''
if command -v addport >/dev/null 2>&1; then
    ADDPORT_BIN="$(command -v addport)"
elif [[ -x "$STORAGE_ROOT/daemon_builder/addport.sh" ]]; then
    ADDPORT_BIN="$STORAGE_ROOT/daemon_builder/addport.sh"
else
    fatal 'addport is not installed. Install/update the SQSYIIMP Stratum manager first.'
fi

if ! "$ADDPORT_BIN" CREATECOIN "$coin_symbol" "$evm_algo"; then
    print_warning 'The node was installed, but addport did not complete successfully.'
    print_info "You can retry with: addport $coin_symbol $evm_algo"
    save_node_metadata "$metadata_file"
    exit 1
fi

# addport rewrites managed metadata; append/preserve the EVM node fields again.
save_node_metadata "$metadata_file"

print_divider
print_header 'Ethash / Etchash Installation Complete'
print_success "$coin_name node and Stratum configuration are installed"
print_info "Node status : sudo systemctl status $service_name --no-pager"
print_info "Node log    : sudo journalctl -u $service_name -f"
print_info "RPC check   : $rpc_helper eth_blockNumber"
print_info "Mining RPC  : $rpc_helper eth_getWork"
print_info "Stratum     : stratum.${coin_symbol,,} status"
print_info "Remove plan : removecoin $coin_symbol --check --purge-node"

if [[ "$generated_wallet" == true ]]; then
    echo
    print_warning "POOL WALLET BACKUP REQUIRED: $datadir/keystore/"
    print_warning 'Keep an offline backup of the keystore and the password. The password is intentionally not stored by SQSYIIMP.'
fi

echo
print_warning 'Pruning does not impose a fixed 3 GB disk cap. The live chain state and databases still require whatever space the network needs.'
echo

exit 0
