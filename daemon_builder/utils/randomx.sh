#!/usr/bin/env bash

############################################################
# SQSYIIMP
# RandomX / CryptoNote node installer for DaemonBuilder
#
# Installs a Monero/CryptoNote-style daemon, wallet CLI,
# wallet RPC and their runtime services.
#
# Stratum source code remains independent. SQSYIIMP may configure
# or compile a selected Stratum repository, but does not modify its
# C/C++ source code.
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
write_wallet_rpc_service() {
    local file="$1"
    local wallet_runner="$2"
    local desc="$3"
    local daemon_service="$4"

    sudo tee "$file" >/dev/null <<EOF_SERVICE
[Unit]
Description=$desc
After=network-online.target $daemon_service
Wants=network-online.target
Requires=$daemon_service

[Service]
Type=simple
User=$STORAGE_USER
Group=$STORAGE_GROUP
ExecStart=$wallet_runner
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
    grep -Ev '^(NODE_TYPE|COIN_NAME|DAEMON_BINARY|CLI_BINARY|TX_BINARY|UTIL_BINARY|HASH_BINARY|WALLET_BINARY|QT_BINARY|DAEMON_DATADIR|DAEMON_CONF|DAEMON_BOOT_LOG|DAEMON_SERVICE|DAEMON_SERVICE_FILE|DAEMON_RUNNER|DAEMON_RPC_PORT|DAEMON_RPC_URL|DAEMON_P2P_PORT|RPC_HELPER_BINARY|POOL_WALLET_FILE|POOL_WALLET_PASSWORD_FILE|WALLET_RPC_BINARY|WALLET_RPC_PORT|WALLET_RPC_URL|WALLET_RPC_SERVICE|WALLET_RPC_SERVICE_FILE|WALLET_RPC_RUNNER)=' "$tmp" > "${tmp}.clean" || true
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
POOL_WALLET_PASSWORD_FILE=${wallet_password_file:-}
WALLET_RPC_BINARY=${installed_wallet_rpc:+$(basename "$installed_wallet_rpc")}
WALLET_RPC_PORT=${wallet_rpc_port:-}
WALLET_RPC_URL=${wallet_rpc_port:+http://127.0.0.1:$wallet_rpc_port}
WALLET_RPC_SERVICE=${wallet_rpc_service_name:-}
WALLET_RPC_SERVICE_FILE=${wallet_rpc_service_file:-}
WALLET_RPC_RUNNER=${wallet_rpc_runner:-}
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
print_info 'This installer manages the RandomX/CryptoNote node, wallet and Wallet RPC runtime.'
print_info 'Stratum source remains independent and is never patched by this installer.'

coin_name=''; input_value 'Coin Name' 'Full coin name (example: Monero)' '' coin_name
[[ -n "${coin_name// }" ]] || fatal 'Coin name cannot be empty'
coin_symbol=''; input_value 'Coin Symbol' 'YiiMP ticker/symbol (example: XMR)' '' coin_symbol
coin_symbol="${coin_symbol^^}"; valid_symbol "$coin_symbol" || fatal "Invalid coin symbol: $coin_symbol"
coin_id="$(printf '%s' "$coin_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]//g')"
input_value 'Coin Identifier' 'Filesystem/service identifier' "$coin_id" coin_id
coin_id="${coin_id,,}"; valid_id "$coin_id" || fatal "Invalid coin identifier: $coin_id"

install_mode=''; choose_menu 'Node Binaries' 'Choose how to provide the CryptoNote binaries.' install_mode \
    local 'Use existing local daemon/wallet executables' \
    download 'Download a precompiled Linux archive' \
    source 'Clone and compile a CryptoNote source repository'

mkdir -p "$TMP_ROOT"; tmpdir="$(mktemp -d "$TMP_ROOT/randomx-${coin_id}.XXXXXX")"
trap 'rm -rf "$tmpdir" 2>/dev/null || true' EXIT
source_daemon=''
source_wallet=''
source_wallet_rpc=''

# Suggest CryptoNote binary names from the coin identifier.
# The user can edit them because not every project follows
# exactly the same naming convention.
daemon_name="${coin_id}d"
wallet_name="${coin_id}-wallet-cli"
wallet_rpc_name="${coin_id}-wallet-rpc"

default_daemon_path="/usr/bin/${daemon_name}"
default_wallet_path="/usr/bin/${wallet_name}"
default_wallet_rpc_path="/usr/bin/${wallet_rpc_name}"


case "$install_mode" in

    local)
        input_value \
            'Daemon Binary' \
            "Absolute path to the CryptoNote daemon executable (suggested: ${default_daemon_path})" \
            "$default_daemon_path" \
            source_daemon

        [[ -x "$source_daemon" ]] ||
            fatal "Daemon executable not found: $source_daemon"

        daemon_name="$(basename "$source_daemon")"

        input_value \
            'Wallet CLI' \
            "Absolute path to wallet CLI (suggested: ${default_wallet_path}); leave empty if unavailable" \
            "$default_wallet_path" \
            source_wallet

        input_value \
            'Wallet RPC' \
            "Absolute path to wallet RPC executable (suggested: ${default_wallet_rpc_path}); leave empty if unavailable" \
            "$default_wallet_rpc_path" \
            source_wallet_rpc

        [[ -z "$source_wallet" || -x "$source_wallet" ]] ||
            fatal "Wallet CLI executable not found: $source_wallet"

        [[ -z "$source_wallet_rpc" || -x "$source_wallet_rpc" ]] ||
            fatal "Wallet RPC executable not found: $source_wallet_rpc"

        [[ -z "$source_wallet" ]] ||
            wallet_name="$(basename "$source_wallet")"

        [[ -z "$source_wallet_rpc" ]] ||
            wallet_rpc_name="$(basename "$source_wallet_rpc")"
        ;;

    download)
        download_url=''
        input_value \
            'Precompiled Package' \
            'Direct URL to a Linux archive containing the daemon and optionally wallet CLI' \
            '' \
            download_url

        [[ "$download_url" =~ ^https?:// ]] ||
            fatal 'A valid http/https URL is required'

        input_value \
            'Daemon Name' \
            'Daemon executable name inside archive (suggested from coin identifier)' \
            "$daemon_name" \
            daemon_name

        input_value \
            'Wallet CLI Name' \
            'Wallet CLI executable name inside archive (suggested from coin identifier); leave empty if unavailable' \
            "$wallet_name" \
            wallet_name

        input_value \
            'Wallet RPC Name' \
            'Wallet RPC executable name inside archive (suggested from coin identifier); leave empty if unavailable' \
            "$wallet_rpc_name" \
            wallet_rpc_name

        download_file="$tmpdir/$(basename "${download_url%%\?*}")"
        [[ -n "${download_file##*/}" ]] ||
            download_file="$tmpdir/package"

        print_status 'Downloading CryptoNote package...'

        curl \
            -fL \
            --retry 3 \
            --connect-timeout 15 \
            "$download_url" \
            -o "$download_file"

        extract_dir="$tmpdir/extracted"
        extract_download "$download_file" "$extract_dir"

        source_daemon="$(
            find "$extract_dir" \
                -type f \
                -name "$daemon_name" \
                -print -quit 2>/dev/null || true
        )"

        [[ -n "$source_daemon" ]] ||
            fatal "Could not find daemon '$daemon_name' in package"

        chmod +x "$source_daemon"

        if [[ -n "$wallet_name" ]]; then
            source_wallet="$(
                find "$extract_dir" \
                    -type f \
                    -name "$wallet_name" \
                    -print -quit 2>/dev/null || true
            )"

            if [[ -n "$source_wallet" ]]; then
                chmod +x "$source_wallet"
            else
                print_warning \
                    "Wallet CLI '$wallet_name' was not extracted/found; continuing without wallet CLI"
                wallet_name=''
            fi
        fi

        if [[ -n "$wallet_rpc_name" ]]; then
            source_wallet_rpc="$(
                find "$extract_dir" \
                    -type f \
                    -name "$wallet_rpc_name" \
                    -print -quit 2>/dev/null || true
            )"

            if [[ -n "$source_wallet_rpc" ]]; then
                chmod +x "$source_wallet_rpc"
                print_success "Wallet RPC found: $wallet_rpc_name"
            else
                print_warning \
                    "Wallet RPC '$wallet_rpc_name' was not extracted/found"
                wallet_rpc_name=''
            fi
        fi
        ;;

    source)
        need_cmd git

        source_repo=''
        source_ref=''
        source_build_system=''
        source_build_jobs='2'
        source_cc=''
        source_cxx=''
        source_build_dir_name='build'
        source_extra_args=''

        input_value \
            'Source Repository' \
            'Git repository URL containing the CryptoNote node source code' \
            '' \
            source_repo

        [[ "$source_repo" =~ ^(https?|git|ssh):// ]] ||
        [[ "$source_repo" =~ ^git@[^:]+:.+ ]] ||
            fatal 'A valid Git repository URL is required'

        input_value \
            'Source Revision' \
            'Optional branch, tag or commit. Leave empty to use repository default HEAD.' \
            '' \
            source_ref

        input_value \
            'Daemon Name' \
            'Daemon executable name expected after compilation' \
            "$daemon_name" \
            daemon_name

        input_value \
            'Wallet CLI Name' \
            'Wallet CLI executable name expected after compilation; leave empty if unavailable' \
            "$wallet_name" \
            wallet_name

        input_value \
            'Wallet RPC Name' \
            'Wallet RPC executable name expected after compilation; leave empty if unavailable' \
            "$wallet_rpc_name" \
            wallet_rpc_name

        choose_menu \
            'Build System' \
            'Choose the source build system used by this CryptoNote repository.' \
            source_build_system \
            cmake 'CMake out-of-tree Release build' \
            make 'GNU Make build in repository root'

        input_value \
            'Build Jobs' \
            'Parallel compilation jobs. Low values reduce memory pressure.' \
            '2' \
            source_build_jobs

        [[ "$source_build_jobs" =~ ^[1-9][0-9]*$ ]] ||
            fatal 'Build jobs must be a positive integer'

        input_value \
            'C Compiler' \
            'Optional C compiler executable/path (example: gcc-9). Leave empty for system default.' \
            '' \
            source_cc

        input_value \
            'C++ Compiler' \
            'Optional C++ compiler executable/path (example: g++-9). Leave empty for system default.' \
            '' \
            source_cxx

        source_dir="$tmpdir/source"

        print_status "Cloning CryptoNote source repository..."

        git clone \
            --recursive \
            "$source_repo" \
            "$source_dir"

        if [[ -n "$source_ref" ]]; then
            print_status "Checking out source revision: $source_ref"

            git -C "$source_dir" checkout "$source_ref"

            git -C "$source_dir" \
                submodule update \
                --init \
                --recursive
        fi

        case "$source_build_system" in

            cmake)
                need_cmd cmake

                input_value \
                    'CMake Build Directory' \
                    'Build directory name inside the temporary source tree' \
                    "$source_build_dir_name" \
                    source_build_dir_name

                [[ "$source_build_dir_name" =~ ^[A-Za-z0-9._-]+$ ]] ||
                    fatal 'Invalid CMake build directory name'

                input_value \
                    'Additional CMake Arguments' \
                    'Optional extra CMake arguments. Leave empty for standard Release build.' \
                    '' \
                    source_extra_args

                declare -a cmake_args=(
                    -S "$source_dir"
                    -B "$source_dir/$source_build_dir_name"
                    -DCMAKE_BUILD_TYPE=Release
                )

                if [[ -n "${source_extra_args// }" ]]; then
                    mapfile -t parsed_cmake_args < <(
                        parse_shell_words "$source_extra_args"
                    )
                    cmake_args+=("${parsed_cmake_args[@]}")
                fi

                print_status \
                    "Configuring CryptoNote source with CMake..."

                if [[ -n "$source_cc" || -n "$source_cxx" ]]; then
                    env_args=()

                    [[ -z "$source_cc" ]] ||
                        env_args+=("CC=$source_cc")

                    [[ -z "$source_cxx" ]] ||
                        env_args+=("CXX=$source_cxx")

                    env "${env_args[@]}" \
                        cmake "${cmake_args[@]}"
                else
                    cmake "${cmake_args[@]}"
                fi

                print_status \
                    "Building CryptoNote source with ${source_build_jobs} parallel job(s)..."

                cmake \
                    --build "$source_dir/$source_build_dir_name" \
                    --parallel "$source_build_jobs"
                ;;

            make)
                need_cmd make

                input_value \
                    'Additional Make Arguments' \
                    'Optional extra Make arguments. Leave empty for the repository default target.' \
                    '' \
                    source_extra_args

                declare -a make_args=()

                if [[ -n "${source_extra_args// }" ]]; then
                    mapfile -t make_args < <(
                        parse_shell_words "$source_extra_args"
                    )
                fi

                print_status \
                    "Building CryptoNote source with ${source_build_jobs} parallel job(s)..."

                if [[ -n "$source_cc" || -n "$source_cxx" ]]; then
                    env_args=()

                    [[ -z "$source_cc" ]] ||
                        env_args+=("CC=$source_cc")

                    [[ -z "$source_cxx" ]] ||
                        env_args+=("CXX=$source_cxx")

                    env "${env_args[@]}" \
                        make \
                        -C "$source_dir" \
                        -j"$source_build_jobs" \
                        "${make_args[@]}"
                else
                    make \
                        -C "$source_dir" \
                        -j"$source_build_jobs" \
                        "${make_args[@]}"
                fi
                ;;

            *)
                fatal "Unsupported source build system: $source_build_system"
                ;;
        esac

        source_daemon="$(
            find "$source_dir" \
                -type f \
                -name "$daemon_name" \
                -perm -u+x \
                -print -quit 2>/dev/null || true
        )"

        if [[ -z "$source_daemon" ]]; then
            source_daemon="$(
                find "$source_dir" \
                    -type f \
                    -name "$daemon_name" \
                    -print -quit 2>/dev/null || true
            )"
        fi

        [[ -n "$source_daemon" && -f "$source_daemon" ]] ||
            fatal \
                "Compiled daemon '$daemon_name' was not found in source tree"

        chmod +x "$source_daemon"

        if [[ -n "$wallet_name" ]]; then
            source_wallet="$(
                find "$source_dir" \
                    -type f \
                    -name "$wallet_name" \
                    -perm -u+x \
                    -print -quit 2>/dev/null || true
            )"

            if [[ -z "$source_wallet" ]]; then
                source_wallet="$(
                    find "$source_dir" \
                        -type f \
                        -name "$wallet_name" \
                        -print -quit 2>/dev/null || true
                )"
            fi

            if [[ -n "$source_wallet" ]]; then
                chmod +x "$source_wallet"
                print_success \
                    "Compiled Wallet CLI found: $source_wallet"
            else
                print_warning \
                    "Compiled Wallet CLI '$wallet_name' was not found"
                wallet_name=''
            fi
        fi

        if [[ -n "$wallet_rpc_name" ]]; then
            source_wallet_rpc="$(
                find "$source_dir" \
                    -type f \
                    -name "$wallet_rpc_name" \
                    -perm -u+x \
                    -print -quit 2>/dev/null || true
            )"

            if [[ -z "$source_wallet_rpc" ]]; then
                source_wallet_rpc="$(
                    find "$source_dir" \
                        -type f \
                        -name "$wallet_rpc_name" \
                        -print -quit 2>/dev/null || true
                )"
            fi

            if [[ -n "$source_wallet_rpc" ]]; then
                chmod +x "$source_wallet_rpc"
                print_success \
                    "Compiled Wallet RPC found: $source_wallet_rpc"
            else
                print_warning \
                    "Compiled Wallet RPC '$wallet_rpc_name' was not found"
                wallet_rpc_name=''
            fi
        fi

        print_success \
            "CryptoNote source compilation completed"
        ;;

    *)
        fatal "Unsupported installation mode: $install_mode"
        ;;
esac

installed_daemon="/usr/bin/${coin_id}d"
installed_wallet=''
installed_wallet_rpc=''

print_status "Installing daemon as $installed_daemon..."
sudo install -o root -g root -m 0755 "$source_daemon" "$installed_daemon"

if [[ -n "$source_wallet" ]]; then
    installed_wallet="/usr/bin/${coin_id}-wallet-cli"
    print_status "Installing wallet CLI as $installed_wallet..."
    sudo install -o root -g root -m 0755 "$source_wallet" "$installed_wallet"
fi

if [[ -n "$source_wallet_rpc" ]]; then
    installed_wallet_rpc="/usr/bin/${coin_id}-wallet-rpc"
    print_status "Installing wallet RPC as $installed_wallet_rpc..."
    sudo install -o root -g root -m 0755 "$source_wallet_rpc" "$installed_wallet_rpc"
fi


# ---------------------------------------------------------
# Runtime dependency validation
# ---------------------------------------------------------

find_mysql_client() {
    if command -v mariadb >/dev/null 2>&1; then
        command -v mariadb
        return 0
    fi

    if command -v mysql >/dev/null 2>&1; then
        command -v mysql
        return 0
    fi

    return 1
}

detect_yiimp_database() {
    local client="$1"
    local cnf="$2"
    local db=""

    db="$(
        sudo "$client" \
            --defaults-extra-file="$cnf" \
            --defaults-group-suffix=mysql \
            -Nse "
SELECT TABLE_SCHEMA
FROM information_schema.TABLES
WHERE TABLE_NAME='coins'
ORDER BY TABLE_SCHEMA
LIMIT 1;
" 2>/dev/null || true
    )"

    printf '%s\n' "$db"
}

sql_escape() {
    local value="${1:-}"
    value="${value//\\/\\\\}"
    value="${value//\'/\'\'}"
    printf '%s' "$value"
}

get_wallet_rpc_address() {
    local port="$1"
    local response=""
    local address=""

    [[ -n "$port" ]] || return 1

    response="$(
        curl -fsS \
            -H 'Content-Type: application/json' \
            -d '{"jsonrpc":"2.0","id":"0","method":"get_address","params":{}}' \
            "http://127.0.0.1:${port}/json_rpc" \
            2>/dev/null || true
    )"

    [[ -n "$response" ]] || return 1

    address="$(
        printf '%s' "$response" |
        python3 -c '
import json, sys
try:
    obj = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)

result = obj.get("result") or {}
address = result.get("address") or ""

if not address:
    addresses = result.get("addresses") or []
    if addresses and isinstance(addresses[0], dict):
        address = addresses[0].get("address") or ""

if address:
    print(address)
'
    )" || return 1

    [[ -n "$address" ]] || return 1
    printf '%s\n' "$address"
}

configure_yiimp_coin() {
    local mysql_cnf="$STORAGE_ROOT/yiimp/.my.cnf"
    local mysql_client=""
    local yiimp_db=""
    local master_wallet=""
    local existing_id=""
    local q_name=""
    local q_symbol=""
    local q_wallet=""
    local q_program=""
    local q_conf_folder=""
    local dedicated_port_sql="NULL"
    local wallet_rpc_port_sql="NULL"

    if ! sudo test -r "$mysql_cnf"; then
        print_warning "YiiMP database credentials file not readable: $mysql_cnf"
        return 1
    fi

    mysql_client="$(find_mysql_client || true)"
    [[ -n "$mysql_client" ]] || {
        print_warning 'MariaDB/MySQL client is not installed'
        return 1
    }

    yiimp_db="$(detect_yiimp_database "$mysql_client" "$mysql_cnf")"

    [[ -n "$yiimp_db" ]] || {
        print_warning 'Could not detect YiiMP database containing the coins table'
        return 1
    }

    if [[ -n "${wallet_rpc_port:-}" ]]; then
        master_wallet="$(get_wallet_rpc_address "$wallet_rpc_port" || true)"
    fi

    if [[ -z "$master_wallet" ]]; then
        input_value \
            'Pool Reward Address' \
            'CryptoNote pool reward address (master_wallet)' \
            '' \
            master_wallet
    else
        print_success "Pool reward address detected from Wallet RPC"
    fi

    [[ -n "$master_wallet" ]] ||
        fatal 'A CryptoNote pool reward address is required'

    block_time_value=''
    input_value \
        'Block Time' \
        'Expected block time in seconds' \
        '120' \
        block_time_value

    [[ "$block_time_value" =~ ^[1-9][0-9]*$ ]] ||
        fatal 'Block time must be a positive integer'

    payout_decimals_value=''
    input_value \
        'Payout Decimals' \
        'Coin decimal precision used for payouts' \
        '12' \
        payout_decimals_value

    [[ "$payout_decimals_value" =~ ^[0-9]+$ ]] ||
        fatal 'Payout decimals must be an integer'

    (( payout_decimals_value >= 0 && payout_decimals_value <= 18 )) ||
        fatal 'Payout decimals must be between 0 and 18'

    q_name="$(sql_escape "$coin_name")"
    q_symbol="$(sql_escape "$coin_symbol")"
    q_wallet="$(sql_escape "$master_wallet")"
    q_program="$(sql_escape "$(basename "$installed_daemon")")"
    q_conf_folder="$(sql_escape "$datadir")"

    if [[ -n "${stratum_port:-}" && "$stratum_port" =~ ^[0-9]+$ ]]; then
        dedicated_port_sql="$stratum_port"
    fi

    if [[ -n "${wallet_rpc_port:-}" && "$wallet_rpc_port" =~ ^[0-9]+$ ]]; then
        wallet_rpc_port_sql="$wallet_rpc_port"
    fi

    existing_id="$(
        sudo "$mysql_client" \
            --defaults-extra-file="$mysql_cnf" \
            --defaults-group-suffix=mysql \
            "$yiimp_db" \
            -Nse "
SELECT id
FROM coins
WHERE symbol='${q_symbol}'
ORDER BY id
LIMIT 1;
" 2>/dev/null || true
    )"

    if [[ -n "$existing_id" ]]; then

        print_status \
            "Updating existing YiiMP coin ${coin_symbol} (id=${existing_id})..."

        sudo "$mysql_client" \
            --defaults-extra-file="$mysql_cnf" \
            --defaults-group-suffix=mysql \
            "$yiimp_db" <<EOF_SQL
UPDATE coins
SET
    name='${q_name}',
    symbol='${q_symbol}',
    symbol2='${q_symbol}',
    algo='randomx',
    master_wallet='${q_wallet}',
    block_time=${block_time_value},
    payout_decimals=${payout_decimals_value},
    rpcencoding='XMR',
    rpchost='127.0.0.1',
    rpcport=${rpc_port},
    rpcuser='',
    rpcpasswd='',
    wallet_rpchost='127.0.0.1',
    wallet_rpcport=${wallet_rpc_port_sql},
    wallet_rpcuser='',
    wallet_rpcpasswd='',
    program='${q_program}',
    conf_folder='${q_conf_folder}',
    installed=1,
    enable=0,
    auto_ready=0,
    visible=0,
    dontsell=1,
    dedicatedport=${dedicated_port_sql}
WHERE id=${existing_id};
EOF_SQL

    else

        print_status \
            "Creating YiiMP coin record for ${coin_symbol}..."

        sudo "$mysql_client" \
            --defaults-extra-file="$mysql_cnf" \
            --defaults-group-suffix=mysql \
            "$yiimp_db" <<EOF_SQL
INSERT INTO coins (
    name,
    symbol,
    symbol2,
    algo,
    master_wallet,
    block_time,
    payout_decimals,
    rpcencoding,
    rpchost,
    rpcport,
    rpcuser,
    rpcpasswd,
    wallet_rpchost,
    wallet_rpcport,
    wallet_rpcuser,
    wallet_rpcpasswd,
    program,
    conf_folder,
    installed,
    enable,
    auto_ready,
    visible,
    dontsell,
    dedicatedport
) VALUES (
    '${q_name}',
    '${q_symbol}',
    '${q_symbol}',
    'randomx',
    '${q_wallet}',
    ${block_time_value},
    ${payout_decimals_value},
    'XMR',
    '127.0.0.1',
    ${rpc_port},
    '',
    '',
    '127.0.0.1',
    ${wallet_rpc_port_sql},
    '',
    '',
    '${q_program}',
    '${q_conf_folder}',
    1,
    0,
    0,
    0,
    1,
    ${dedicated_port_sql}
);
EOF_SQL
    fi

    print_success \
        "YiiMP coin record configured for ${coin_symbol}"

    print_warning \
        'Coin remains disabled until the CryptoNote node is synchronized.'
}

check_binary_dependencies() {
    local binary="$1"
    local label="$2"
    local ldd_output missing

    [[ -n "$binary" && -x "$binary" ]] || return 0

    if ! command -v ldd >/dev/null 2>&1; then
        print_warning "ldd is unavailable; dependency check skipped for $label"
        return 0
    fi

    ldd_output="$(ldd "$binary" 2>&1 || true)"
    missing="$(printf '%s\n' "$ldd_output" | awk '/=> not found/ {print $1}')"

    if [[ -n "$missing" ]]; then
        print_warning "$label has missing runtime libraries:"
        while IFS= read -r lib; do
            [[ -n "$lib" ]] && printf '   - %s\n' "$lib"
        done <<< "$missing"
        return 1
    fi

    print_success "$label runtime dependencies are available"
    return 0
}

daemon_dependencies_ok=1

if ! check_binary_dependencies "$installed_daemon" "CryptoNote daemon"; then
    daemon_dependencies_ok=0
fi

if [[ -n "$installed_wallet_rpc" ]]; then
    check_binary_dependencies "$installed_wallet_rpc" "CryptoNote wallet RPC" ||         print_warning 'Wallet RPC will not be started until its dependencies are resolved'
fi

if [[ -n "$installed_wallet" ]]; then
    check_binary_dependencies "$installed_wallet" "CryptoNote wallet CLI" ||         print_warning 'Wallet CLI is installed but currently cannot run'
fi


rpc_port="$(find_free_tcp_port 18081 18999 || true)"
[[ -n "$rpc_port" ]] || fatal 'No free daemon RPC port found'

input_value     'Daemon RPC Port'     'Local CryptoNote daemon RPC port'     "$rpc_port"     rpc_port

valid_port "$rpc_port" || fatal 'Invalid daemon RPC port'
port_is_free_tcp "$rpc_port" || fatal 'Daemon RPC port is already in use'


wallet_rpc_port=''

if [[ -n "$installed_wallet_rpc" ]]; then
    wallet_rpc_port="$(find_free_tcp_port 18083 18999 || true)"
    [[ -n "$wallet_rpc_port" ]] || fatal 'No free Wallet RPC port found'

    input_value         'Wallet RPC Port'         'Local CryptoNote wallet RPC port used by YiiMP'         "$wallet_rpc_port"         wallet_rpc_port

    valid_port "$wallet_rpc_port" || fatal 'Invalid Wallet RPC port'
    port_is_free_tcp "$wallet_rpc_port" || fatal 'Wallet RPC port is already in use'

    [[ "$wallet_rpc_port" != "$rpc_port" ]] ||         fatal 'Wallet RPC port must be different from daemon RPC port'
fi


p2p_port="$(find_free_tcp_port 18080 18999 || true)"
[[ -n "$p2p_port" ]] || fatal 'No free P2P port found'

input_value     'P2P Port'     'CryptoNote peer-to-peer port'     "$p2p_port"     p2p_port

valid_port "$p2p_port" || fatal 'Invalid P2P port'
port_is_free_tcp "$p2p_port" || fatal 'P2P port is already in use'

[[ "$p2p_port" != "$rpc_port" ]] ||     fatal 'P2P port must be different from daemon RPC port'

[[ -z "$wallet_rpc_port" || "$p2p_port" != "$wallet_rpc_port" ]] ||     fatal 'P2P port must be different from Wallet RPC port'

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
wallet_password_file=''
wallet_rpc_runner=''
wallet_rpc_service_name=''
wallet_rpc_service_file=''

if [[ -n "$installed_wallet" ]]; then
    wallet_mode=''
    choose_menu \
        'Pool Wallet' \
        'Choose whether to create a local CryptoNote pool wallet now.' \
        wallet_mode \
        skip 'Skip wallet creation / use an existing external reward address' \
        create 'Create a new local encrypted pool wallet'

    if [[ "$wallet_mode" == create ]]; then

        wallet_dir="$datadir/wallet"
        wallet_file="$wallet_dir/pool"
        wallet_password_file="$wallet_dir/pool.password"

        sudo install \
            -d \
            -o "$STORAGE_USER" \
            -g "$STORAGE_GROUP" \
            -m 0700 \
            "$wallet_dir"

        password_mode=''
        choose_menu \
            'Pool Wallet Password' \
            'Choose how the pool wallet password will be created.' \
            password_mode \
            generate 'Generate a strong random password and store it securely' \
            manual 'Enter the wallet password manually'

        if [[ "$password_mode" == generate ]]; then
            need_cmd openssl

            sudo -u "$STORAGE_USER" bash -c \
                "umask 077; openssl rand -base64 32 > '$wallet_password_file'"

        else
            wallet_password=''
            wallet_password_confirm=''

            input_secret \
                'New Pool Wallet' \
                'Password for the new encrypted wallet' \
                wallet_password

            [[ -n "$wallet_password" ]] ||
                fatal 'Wallet password cannot be empty'

            input_secret \
                'Confirm Wallet Password' \
                'Repeat the wallet password' \
                wallet_password_confirm

            [[ "$wallet_password" == "$wallet_password_confirm" ]] ||
                fatal 'Wallet passwords do not match'

            printf '%s\n' "$wallet_password" |
                sudo -u "$STORAGE_USER" tee "$wallet_password_file" >/dev/null

            sudo -u "$STORAGE_USER" chmod 0600 "$wallet_password_file"

            wallet_password=''
            wallet_password_confirm=''
        fi

        sudo chown \
            "$STORAGE_USER:$STORAGE_GROUP" \
            "$wallet_password_file"

        sudo chmod 0600 "$wallet_password_file"

        print_status "Creating encrypted wallet: $wallet_file"

        if ! sudo -u "$STORAGE_USER" "$installed_wallet" \
            --generate-new-wallet "$wallet_file" \
            --password-file "$wallet_password_file" \
            --mnemonic-language English \
            --command exit
        then
            fatal 'Wallet creation failed. Check this coin wallet-cli arguments.'
        fi

        print_success "Wallet created: $wallet_file"
        print_info "Wallet password file: $wallet_password_file"
        print_warning 'Back up the wallet seed offline. Never expose the seed or password file.'
    fi
fi

runner="/usr/local/lib/sqsyiimp/${coin_id}-randomx-node"
service_name="sqsyiimp-${coin_id}-node.service"
service_file="/etc/systemd/system/$service_name"
declare -a runtime_args=(--data-dir "$datadir" --rpc-bind-ip 127.0.0.1 --rpc-bind-port "$rpc_port" --p2p-bind-port "$p2p_port" --non-interactive)
runtime_args+=("${extra_args[@]}")
write_runner "$runner" "$installed_daemon" "${runtime_args[@]}"
write_systemd_service "$service_file" "$runner" "SQSYIIMP ${coin_name} RandomX/CryptoNote node"

wallet_rpc_dependencies_ok=1

if [[ -n "$installed_wallet_rpc" ]]; then
    if ! check_binary_dependencies \
        "$installed_wallet_rpc" \
        "CryptoNote wallet RPC"
    then
        wallet_rpc_dependencies_ok=0
    fi
fi

if [[ "$daemon_dependencies_ok" -eq 1 ]]; then
    if confirm_yesno 'Start RandomX Node' "Start ${coin_name} now and enable it at boot?"; then
        sudo systemctl enable --now "$service_name"
        sleep 2

        if sudo systemctl is-active --quiet "$service_name"; then
            print_success 'CryptoNote node service is running'
        else
            print_warning "Service did not remain active; inspect:"
            print_warning "sudo journalctl -u $service_name -n 100 --no-pager"
        fi
    fi
else
    print_warning 'Node service was created but will NOT be started.'
    print_warning 'Resolve the missing daemon libraries first, then start the service manually.'
fi

if [[ -n "$installed_wallet_rpc" ]] &&
   [[ -n "$wallet_file" ]] &&
   [[ -n "$wallet_password_file" ]]
then

    wallet_rpc_runner="/usr/local/lib/sqsyiimp/${coin_id}-randomx-wallet-rpc"
    wallet_rpc_service_name="sqsyiimp-${coin_id}-wallet-rpc.service"
    wallet_rpc_service_file="/etc/systemd/system/$wallet_rpc_service_name"

    declare -a wallet_rpc_args=(
        --wallet-file "$wallet_file"
        --password-file "$wallet_password_file"
        --daemon-address "127.0.0.1:$rpc_port"
        --rpc-bind-ip 127.0.0.1
        --rpc-bind-port "$wallet_rpc_port"
        --disable-rpc-login
    )

    write_runner \
        "$wallet_rpc_runner" \
        "$installed_wallet_rpc" \
        "${wallet_rpc_args[@]}"

    write_wallet_rpc_service \
        "$wallet_rpc_service_file" \
        "$wallet_rpc_runner" \
        "SQSYIIMP ${coin_name} Wallet RPC" \
        "$service_name"

    if [[ "$wallet_rpc_dependencies_ok" -eq 1 ]] &&
       sudo systemctl is-active --quiet "$service_name"
    then
        if confirm_yesno \
            'Start Wallet RPC' \
            "Start ${coin_name} Wallet RPC now and enable it at boot?"
        then
            sudo systemctl enable --now "$wallet_rpc_service_name"
            sleep 2

            if sudo systemctl is-active --quiet "$wallet_rpc_service_name"; then
                print_success 'CryptoNote Wallet RPC service is running'
            else
                print_warning 'Wallet RPC service did not remain active; inspect:'
                print_warning \
                    "sudo journalctl -u $wallet_rpc_service_name -n 100 --no-pager"
            fi
        fi
    else
        print_warning \
            'Wallet RPC service was created but was not started automatically.'
    fi
elif [[ -n "$installed_wallet_rpc" ]]; then
    print_warning \
        'Wallet RPC binary is installed, but no local pool wallet/password file is configured.'
fi

metadata_file="$MANAGED_DIR/${coin_symbol,,}.conf"
save_node_metadata "$metadata_file"

# ---------------------------------------------------------
# Dedicated RandomX Stratum configuration
# ---------------------------------------------------------

stratum_configured=0
stratum_port=''
stratum_binary=''
stratum_config=''

if command -v addport >/dev/null 2>&1; then

    if confirm_yesno \
        'RandomX Stratum' \
        "Configure a dedicated RandomX Stratum for ${coin_symbol} now?"
    then

        print_status \
            'Creating RandomX Stratum configuration. Automatic start will be deferred.'

        rm -f "$STORAGE_ROOT/daemon_builder/.addport.cnf"

        if SQSYIIMP_STRATUM_DEFER_START=true \
            addport CREATECOIN "$coin_symbol" randomx
        then
            ADDPORTCONF="$STORAGE_ROOT/daemon_builder/.addport.cnf"

            if [[ -r "$ADDPORTCONF" ]]; then
                # shellcheck disable=SC1090
                source "$ADDPORTCONF"

                stratum_port="${COINPORT:-}"
                stratum_binary="${STRATUMBINARY:-}"
                stratum_config="${STRATUMCONFIG:-}"

                stratum_configured=1

                print_success \
                    "RandomX Stratum configuration created for ${coin_symbol}"

                [[ -z "$stratum_port" ]] ||
                    print_info "Stratum port   : $stratum_port"

                [[ -z "$stratum_binary" ]] ||
                    print_info "Stratum binary : $stratum_binary"

                [[ -z "$stratum_config" ]] ||
                    print_info "Stratum config : $stratum_config"

                print_info \
                    "Stratum remains stopped until the CryptoNote node is synchronized."

                print_info \
                    "Start later: sudo /usr/bin/stratum.${coin_symbol,,} start"
            else
                print_warning \
                    'addport completed but did not create .addport.cnf'
            fi
        else
            print_warning \
                'RandomX Stratum configuration was not completed.'
        fi
    fi

else
    print_warning \
        'addport command is unavailable; RandomX Stratum configuration was skipped.'
fi

# DaemonBuilder metadata may have been rewritten by addport.
# Re-save node/wallet RPC metadata while preserving the Stratum keys.
save_node_metadata "$metadata_file"

# ---------------------------------------------------------
# YiiMP coin database configuration
# ---------------------------------------------------------

if confirm_yesno \
    'YiiMP Coin Database' \
    "Create or update the YiiMP coin record for ${coin_symbol}?"
then
    configure_yiimp_coin || \
        print_warning 'YiiMP coin database configuration was not completed.'
fi

print_divider
print_header 'RandomX / CryptoNote Installation Complete'
print_success "$coin_name node/wallet installation is complete"
print_info "Node status : sudo systemctl status $service_name --no-pager"
print_info "Node log    : sudo journalctl -u $service_name -f"
print_info "Daemon RPC  : http://127.0.0.1:$rpc_port"
[[ -z "$wallet_rpc_port" ]] || print_info "Wallet RPC  : http://127.0.0.1:$wallet_rpc_port"
[[ -z "$installed_wallet_rpc" ]] || print_info "Wallet RPC binary : $installed_wallet_rpc"
[[ -z "$wallet_file" ]] || print_info "Wallet file : $wallet_file"
[[ -z "$wallet_password_file" ]] || print_info "Wallet password file : $wallet_password_file"
[[ -z "$wallet_rpc_service_name" ]] || print_info "Wallet RPC status : sudo systemctl status $wallet_rpc_service_name --no-pager"

if [[ "${stratum_configured:-0}" -eq 1 ]]; then
    print_info "Stratum port   : ${stratum_port:-unknown}"
    print_info "Stratum binary : ${stratum_binary:-unknown}"
    print_info "Stratum status : sudo /usr/bin/stratum.${coin_symbol,,} status"
    print_info "Stratum start  : sudo /usr/bin/stratum.${coin_symbol,,} start"
    print_warning 'Leave Stratum stopped until the CryptoNote daemon is fully synchronized.'
fi

print_info 'Stratum source code remains independent and is not modified by this installer.'
print_warning 'Verify the coin-specific YiiMP RPC/coin fields before enabling production payouts; CryptoNote coins are not Bitcoin-RPC compatible.'
