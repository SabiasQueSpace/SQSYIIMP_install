#!/usr/bin/env bash

############################################################
# SQSYIIMP
# RandomX / CryptoNote node installer for DaemonBuilder
#
# Installs a Monero/CryptoNote-style daemon and optional
# wallet CLI and creates a systemd node service.
#
# IMPORTANT: SQSYIIMP_install is independent from Stratum source code.
# This script does NOT download, build, install, or modify any Stratum binary.
############################################################

set -euo pipefail

[[ -r /etc/daemonbuilder.sh ]] && source /etc/daemonbuilder.sh
[[ -r /etc/functions.sh ]] && source /etc/functions.sh
[[ -r /etc/yiimpool.conf ]] && source /etc/yiimpool.conf

STORAGE_USER="${STORAGE_USER:-crypto-data}"
STORAGE_GROUP="${STORAGE_GROUP:-$STORAGE_USER}"
STORAGE_ROOT="${STORAGE_ROOT:-/home/$STORAGE_USER}"
STRATUM_DIR="${PATH_STRATUM:-$STORAGE_ROOT/yiimp/site/stratum}"
MANAGED_DIR="$STRATUM_DIR/managed"
TMP_ROOT="${TMPDIR:-/tmp}"

if ! declare -F print_header >/dev/null 2>&1; then
    print_header()  { printf '\n=== %s ===\n\n' "$1"; }
    print_status()  { printf '[*] %s\n' "$1"; }
    print_error()   { printf 'ERROR: %s\n' "$1" >&2; }
    print_warning() { printf 'WARNING: %s\n' "$1" >&2; }
    print_success() { printf 'SUCCESS: %s\n' "$1"; }
    print_info()    { printf 'INFO: %s\n' "$1"; }
    print_divider() { printf '%s\n' '------------------------------------------------------------'; }
fi

fatal() { print_error "$1"; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || fatal "Required command not found: $1"; }
valid_id() { [[ "${1:-}" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; }
valid_symbol() { [[ "${1:-}" =~ ^[A-Z0-9][A-Z0-9_-]*$ ]]; }
valid_port() { [[ "${1:-}" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 )); }
port_is_free_tcp() { local p="$1"; ! ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)${p}$"; }
find_free_tcp_port() {
    local start="$1" end="$2" p
    for ((p=start; p<=end; p++)); do port_is_free_tcp "$p" && { printf '%s\n' "$p"; return 0; }; done
    return 1
}
input_value() {
    local title="$1" text="$2" default_value="$3" __var="$4" value=""
    if command -v dialog >/dev/null 2>&1 && [[ -t 0 && -t 1 ]]; then
        value="$(dialog --stdout --backtitle 'SQSYIIMP' --title "$title" --inputbox "$text" 18 82 "$default_value")" || exit 0
    else
        read -r -e -p "$text [$default_value]: " value
        value="${value:-$default_value}"
    fi
    printf -v "$__var" '%s' "$value"
}
input_secret() {
    local title="$1" text="$2" __var="$3" value=""
    if command -v dialog >/dev/null 2>&1 && [[ -t 0 && -t 1 ]]; then
        value="$(dialog --stdout --backtitle 'SQSYIIMP' --title "$title" --insecure --passwordbox "$text" 16 82)" || exit 0
    else
        read -r -s -p "$text: " value; echo
    fi
    printf -v "$__var" '%s' "$value"
}
choose_menu() {
    local title="$1" text="$2" __var="$3" value=""; shift 3
    if command -v dialog >/dev/null 2>&1 && [[ -t 0 && -t 1 ]]; then
        value="$(dialog --stdout --backtitle 'SQSYIIMP' --title "$title" --menu "$text" 19 82 9 "$@")" || exit 0
    else
        local -a values=() labels=(); local i
        while (($#)); do values+=("$1"); labels+=("$2"); shift 2; done
        printf '%s\n' "$text"
        for i in "${!values[@]}"; do printf '  %d) %s\n' "$((i+1))" "${labels[$i]}"; done
        read -r -p 'Selection: ' i
        [[ "$i" =~ ^[0-9]+$ ]] || fatal 'Invalid selection'
        (( i >= 1 && i <= ${#values[@]} )) || fatal 'Invalid selection'
        value="${values[$((i-1))]}"
    fi
    printf -v "$__var" '%s' "$value"
}
confirm_yesno() {
    local title="$1" text="$2" answer=""
    if command -v dialog >/dev/null 2>&1 && [[ -t 0 && -t 1 ]]; then
        dialog --backtitle 'SQSYIIMP' --title "$title" --yesno "$text" 16 78
        return $?
    fi
    read -r -p "$text [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]]
}
extract_download() {
    local src="$1" dst="$2"; mkdir -p "$dst"
    case "$src" in
        *.tar.gz|*.tgz) tar -xzf "$src" -C "$dst" ;;
        *.tar.xz|*.txz) tar -xJf "$src" -C "$dst" ;;
        *.tar.bz2|*.tbz2) tar -xjf "$src" -C "$dst" ;;
        *.zip) unzip -q "$src" -d "$dst" ;;
        *.7z) 7z x -y -o"$dst" "$src" >/dev/null ;;
        *.rar)
            # Prefer 7z for RAR5, then fall back to unar.
            # A RAR extractor may return a non-zero status even when
            # some usable binaries were extracted successfully.
            rar_ok=0

            if command -v 7z >/dev/null 2>&1; then
                if 7z x -y -o"$dst" "$src"; then
                    rar_ok=1
                else
                    print_warning "7z could not fully extract RAR archive; trying unar fallback"
                    rm -rf "$dst"
                    mkdir -p "$dst"
                fi
            fi

            if [[ "$rar_ok" -eq 0 ]] && command -v unar >/dev/null 2>&1; then
                if unar -f -o "$dst" "$src"; then
                    rar_ok=1
                else
                    print_warning "RAR archive was only partially extracted; checking available binaries"
                fi
            fi

            if [[ "$rar_ok" -eq 0 ]] && [[ -z "$(find "$dst" -type f -print -quit 2>/dev/null)" ]]; then
                fatal "RAR extraction failed and no files were recovered"
            fi
            ;;
        *) cp -f "$src" "$dst/$(basename "$src")" ;;
    esac
}
parse_shell_words() {
    python3 - "$1" <<'PY_PARSE'
import shlex, sys
for item in shlex.split(sys.argv[1]): print(item)
PY_PARSE
}
write_runner() {
    local runner="$1" binary="$2"; shift 2; local arg
    sudo install -d -o root -g root -m 0755 /usr/local/lib/sqsyiimp
    {
        echo '#!/usr/bin/env bash'; echo 'set -e'; printf 'exec %q' "$binary"
        for arg in "$@"; do printf ' %q' "$arg"; done
        echo
    } | sudo tee "$runner" >/dev/null
    sudo chmod 0755 "$runner"
}
write_systemd_service() {
    local file="$1" runner="$2" desc="$3"
    sudo tee "$file" >/dev/null <<EOF_SERVICE
[Unit]
Description=$desc
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$STORAGE_USER
Group=$STORAGE_GROUP
ExecStart=$runner
Restart=on-failure
RestartSec=10
TimeoutStopSec=180
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF_SERVICE
    sudo chmod 0644 "$file"
    sudo systemctl daemon-reload
}
save_node_metadata() {
    local file="$1" tmp; tmp="$(mktemp)"
    sudo mkdir -p "$MANAGED_DIR"
    if [[ -r "$file" ]]; then
        grep -E '^(FORMAT|SYMBOL|WALLET_SYMBOL|ID|ALGO|PORT|STRATUM_BINARY|STRATUM_CONFIG|STRATUM_SERVICE|STRATUM_WRAPPER|STRATUM_LOG|STRATUM_BOOT_LOG)=' "$file" > "$tmp" || true
    else
        cat > "$tmp" <<EOF_BASE
FORMAT=1
SYMBOL=$coin_symbol
WALLET_SYMBOL=$coin_symbol
ID=$coin_id
EOF_BASE
    fi
    grep -Ev '^(NODE_TYPE|COIN_NAME|DAEMON_BINARY|CLI_BINARY|TX_BINARY|UTIL_BINARY|HASH_BINARY|WALLET_BINARY|QT_BINARY|DAEMON_DATADIR|DAEMON_CONF|DAEMON_BOOT_LOG|DAEMON_SERVICE|DAEMON_SERVICE_FILE|DAEMON_RUNNER|DAEMON_RPC_PORT|DAEMON_RPC_URL|DAEMON_P2P_PORT|RPC_HELPER_BINARY|POOL_WALLET_FILE)=' "$tmp" > "${tmp}.clean" || true
    mv "${tmp}.clean" "$tmp"
    cat >> "$tmp" <<EOF_NODE
NODE_TYPE=cryptonote
COIN_NAME=$coin_id
DAEMON_BINARY=$(basename "$installed_daemon")
CLI_BINARY=
TX_BINARY=
UTIL_BINARY=
HASH_BINARY=
WALLET_BINARY=${installed_wallet:+$(basename "$installed_wallet")}
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
RPC_HELPER_BINARY=
POOL_WALLET_FILE=${wallet_file:-}
EOF_NODE
    sudo install -o root -g root -m 0644 "$tmp" "$file"
    rm -f "$tmp"
}

need_cmd python3; need_cmd ss; need_cmd curl; need_cmd systemctl
[[ "$EUID" -ne 0 ]] || fatal 'Run daemonbuilder as a regular administrative user, not root.'
id "$STORAGE_USER" >/dev/null 2>&1 || fatal "Storage user does not exist: $STORAGE_USER"

clear 2>/dev/null || true
print_header 'RandomX / CryptoNote Coin Installation'
print_info 'This mode is for Monero/CryptoNote-style RandomX nodes.'
print_info 'This installer manages only the RandomX/CryptoNote node and wallet.'
print_info 'Stratum source code and binaries are managed independently from SQSYIIMP_install.'

coin_name=''; input_value 'Coin Name' 'Full coin name (example: Monero)' '' coin_name
[[ -n "${coin_name// }" ]] || fatal 'Coin name cannot be empty'
coin_symbol=''; input_value 'Coin Symbol' 'YiiMP ticker/symbol (example: XMR)' '' coin_symbol
coin_symbol="${coin_symbol^^}"; valid_symbol "$coin_symbol" || fatal "Invalid coin symbol: $coin_symbol"
coin_id="$(printf '%s' "$coin_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]//g')"
input_value 'Coin Identifier' 'Filesystem/service identifier' "$coin_id" coin_id
coin_id="${coin_id,,}"; valid_id "$coin_id" || fatal "Invalid coin identifier: $coin_id"

install_mode=''; choose_menu 'Node Binaries' 'Choose how to provide the CryptoNote binaries.' install_mode \
    local 'Use existing local daemon/wallet executables' \
    download 'Download a precompiled Linux archive'

mkdir -p "$TMP_ROOT"; tmpdir="$(mktemp -d "$TMP_ROOT/randomx-${coin_id}.XXXXXX")"
trap 'rm -rf "$tmpdir" 2>/dev/null || true' EXIT
source_daemon=''
source_wallet=''

# Suggest CryptoNote binary names from the coin identifier.
# The user can edit them because not every project follows
# exactly the same naming convention.
daemon_name="${coin_id}d"
wallet_name="${coin_id}-wallet-cli"

default_daemon_path="/usr/bin/${daemon_name}"
default_wallet_path="/usr/bin/${wallet_name}"


if [[ "$install_mode" == local ]]; then
    input_value 'Daemon Binary' "Absolute path to the CryptoNote daemon executable (suggested: ${default_daemon_path})" "$default_daemon_path" source_daemon
    [[ -x "$source_daemon" ]] || fatal "Daemon executable not found: $source_daemon"
    daemon_name="$(basename "$source_daemon")"
    input_value 'Wallet CLI' "Absolute path to wallet CLI (suggested: ${default_wallet_path}); leave empty if unavailable" "$default_wallet_path" source_wallet
    [[ -z "$source_wallet" || -x "$source_wallet" ]] || fatal "Wallet executable not found: $source_wallet"
    [[ -z "$source_wallet" ]] || wallet_name="$(basename "$source_wallet")"
else
    download_url=''; input_value 'Precompiled Package' 'Direct URL to a Linux archive containing the daemon and optionally wallet CLI' '' download_url
    [[ "$download_url" =~ ^https?:// ]] || fatal 'A valid http/https URL is required'
    input_value 'Daemon Name' "Daemon executable name inside archive (suggested from coin identifier)" "$daemon_name" daemon_name
    input_value 'Wallet CLI Name' "Wallet CLI executable name inside archive (suggested from coin identifier); leave empty if unavailable" "$wallet_name" wallet_name
    download_file="$tmpdir/$(basename "${download_url%%\?*}")"; [[ -n "${download_file##*/}" ]] || download_file="$tmpdir/package"
    print_status 'Downloading CryptoNote package...'; curl -fL --retry 3 --connect-timeout 15 "$download_url" -o "$download_file"
    extract_dir="$tmpdir/extracted"; extract_download "$download_file" "$extract_dir"
    source_daemon="$(find "$extract_dir" -type f -name "$daemon_name" -print -quit 2>/dev/null || true)"
    [[ -n "$source_daemon" ]] || fatal "Could not find daemon '$daemon_name' in package"
    chmod +x "$source_daemon"
    if [[ -n "$wallet_name" ]]; then
        source_wallet="$(find "$extract_dir" -type f -name "$wallet_name" -print -quit 2>/dev/null || true)"

        if [[ -n "$source_wallet" ]]; then
            chmod +x "$source_wallet"
        else
            print_warning "Wallet CLI '$wallet_name' was not extracted/found; continuing with daemon only"
            wallet_name=''
        fi
    fi
fi

installed_daemon="/usr/bin/${coin_id}d"
installed_wallet=''
print_status "Installing daemon as $installed_daemon..."
sudo install -o root -g root -m 0755 "$source_daemon" "$installed_daemon"
if [[ -n "$source_wallet" ]]; then
    installed_wallet="/usr/bin/${coin_id}-wallet-cli"
    print_status "Installing wallet CLI as $installed_wallet..."
    sudo install -o root -g root -m 0755 "$source_wallet" "$installed_wallet"
fi

rpc_port="$(find_free_tcp_port 18081 18999 || true)"; [[ -n "$rpc_port" ]] || fatal 'No free RPC port found'
input_value 'Daemon RPC Port' 'Local CryptoNote daemon RPC port' "$rpc_port" rpc_port; valid_port "$rpc_port" || fatal 'Invalid RPC port'; port_is_free_tcp "$rpc_port" || fatal 'RPC port is already in use'
p2p_port="$(find_free_tcp_port 18080 18999 || true)"; [[ -n "$p2p_port" ]] || fatal 'No free P2P port found'
input_value 'P2P Port' 'CryptoNote peer-to-peer port' "$p2p_port" p2p_port; valid_port "$p2p_port" || fatal 'Invalid P2P port'; port_is_free_tcp "$p2p_port" || fatal 'P2P port is already in use'

# Extra daemon arguments are optional.
# Most CryptoNote/RandomX nodes do not need anything here.
declare -a extra_args=()

if confirm_yesno     'Advanced Daemon Arguments'     'Most coins do not need additional daemon arguments.

Only configure this if the coin documentation requires extra options.

Configure additional daemon arguments?'
then
    extra_args_text=''
    input_value         'Additional Daemon Arguments'         'Optional coin/network-specific daemon arguments.

Example:
--add-exclusive-node 1.2.3.4:12345

Leave empty if no additional arguments are required.'         ''         extra_args_text

    if [[ -n "${extra_args_text// }" ]]; then
        mapfile -t extra_args < <(parse_shell_words "$extra_args_text")
    fi
fi

datadir="$STORAGE_ROOT/wallets/.${coin_id}"
sudo install -d -o "$STORAGE_USER" -g "$STORAGE_GROUP" -m 0750 "$STORAGE_ROOT/wallets" "$datadir"

wallet_file=''
if [[ -n "$installed_wallet" ]]; then
    wallet_mode=''; choose_menu 'Pool Wallet' 'Choose whether to create a local CryptoNote wallet now.' wallet_mode \
        skip 'Skip wallet creation / use an existing external reward address' \
        create 'Create a new local encrypted wallet'
    if [[ "$wallet_mode" == create ]]; then
        wallet_file="$datadir/${coin_id}-pool-wallet"
        wallet_password=''; wallet_password_confirm=''
        input_secret 'New Pool Wallet' 'Password for the new encrypted wallet' wallet_password
        [[ -n "$wallet_password" ]] || fatal 'Wallet password cannot be empty'
        input_secret 'Confirm Wallet Password' 'Repeat the wallet password' wallet_password_confirm
        [[ "$wallet_password" == "$wallet_password_confirm" ]] || fatal 'Wallet passwords do not match'
        passfile="$(sudo -u "$STORAGE_USER" mktemp "/tmp/sqsyiimp-${coin_id}-wallet.XXXXXX")"
        printf '%s\n' "$wallet_password" | sudo -u "$STORAGE_USER" tee "$passfile" >/dev/null
        sudo -u "$STORAGE_USER" chmod 0600 "$passfile"
        print_status "Creating encrypted wallet: $wallet_file"
        if ! sudo -u "$STORAGE_USER" "$installed_wallet" \
            --generate-new-wallet "$wallet_file" \
            --password-file "$passfile" \
            --mnemonic-language English \
            --command exit; then
            sudo rm -f "$passfile"; fatal 'Wallet creation failed. Check this coin wallet-cli arguments.'
        fi
        sudo rm -f "$passfile"; wallet_password=''; wallet_password_confirm=''
        print_success "Wallet created: $wallet_file"
        print_warning 'Back up the wallet files and seed immediately. SQSYIIMP does not store the password.'
    fi
fi

runner="/usr/local/lib/sqsyiimp/${coin_id}-randomx-node"
service_name="sqsyiimp-${coin_id}-node.service"
service_file="/etc/systemd/system/$service_name"
declare -a runtime_args=(--data-dir "$datadir" --rpc-bind-ip 127.0.0.1 --rpc-bind-port "$rpc_port" --p2p-bind-port "$p2p_port" --non-interactive)
runtime_args+=("${extra_args[@]}")
write_runner "$runner" "$installed_daemon" "${runtime_args[@]}"
write_systemd_service "$service_file" "$runner" "SQSYIIMP ${coin_name} RandomX/CryptoNote node"

if confirm_yesno 'Start RandomX Node' "Start ${coin_name} now and enable it at boot?"; then
    sudo systemctl enable --now "$service_name"
    sleep 2
    sudo systemctl is-active --quiet "$service_name" && print_success 'CryptoNote node service is running' || print_warning "Service did not remain active; inspect: sudo journalctl -u $service_name -n 100 --no-pager"
fi

metadata_file="$MANAGED_DIR/${coin_symbol,,}.conf"
save_node_metadata "$metadata_file"

print_divider
print_header 'RandomX / CryptoNote Installation Complete'
print_success "$coin_name node/wallet installation is complete"
print_info "Node status : sudo systemctl status $service_name --no-pager"
print_info "Node log    : sudo journalctl -u $service_name -f"
print_info "Daemon RPC  : http://127.0.0.1:$rpc_port"
[[ -z "$wallet_file" ]] || print_info "Wallet file : $wallet_file"
print_info 'Stratum binaries/source are intentionally not managed by SQSYIIMP_install.'
print_warning 'Verify the coin-specific YiiMP RPC/coin fields before enabling production payouts; CryptoNote coins are not Bitcoin-RPC compatible.'
