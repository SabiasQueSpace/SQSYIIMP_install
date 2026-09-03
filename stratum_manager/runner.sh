#!/usr/bin/env bash

############################################################
# Stratum Runner
# SabiasQue.Space
#
# Reads [RUNTIME] binary from a Stratum config and launches
# that executable. Legacy configs without [RUNTIME] continue
# to use the default ./stratum binary.
############################################################

[ -f /etc/yiimpool.conf ] && source /etc/yiimpool.conf
if [ -n "${STORAGE_ROOT:-}" ] && [ -f "$STORAGE_ROOT/yiimp/.yiimp.conf" ]; then
    source "$STORAGE_ROOT/yiimp/.yiimp.conf"
fi

STORAGE_USER="${STORAGE_USER:-crypto-data}"
STORAGE_ROOT="${STORAGE_ROOT:-/home/${STORAGE_USER}}"

STRATUM_DIR="${STRATUM_RUNTIME_DIR:-${SQS_STRATUM_DIR:-${STORAGE_ROOT}/yiimp/site/stratum}}"
CONFIG_DIR="$STRATUM_DIR/config"
DEFAULT_BINARY="stratum"
RESTART_DELAY="${STRATUM_RESTART_DELAY:-${SQS_STRATUM_RESTART_DELAY:-2}}"
STRATUM_LOG_DIR="${STRATUM_LOG_DIR:-/var/log}"

usage() {
    echo "Usage: $0 [--resolve] <config-file>" >&2
}

resolve_config_path() {
    local input="$1"

    if [ -f "$input" ]; then
        printf '%s\n' "$input"
        return 0
    fi

    if [ -f "$CONFIG_DIR/$input" ]; then
        printf '%s\n' "$CONFIG_DIR/$input"
        return 0
    fi

    return 1
}

read_runtime_binary() {
    local config="$1"
    local value

    value=$(awk '
        BEGIN { in_runtime = 0 }
        /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
            section = $0
            gsub(/^[[:space:]]*\[/, "", section)
            gsub(/\][[:space:]]*$/, "", section)
            in_runtime = (tolower(section) == "runtime")
            next
        }
        in_runtime && /^[[:space:]]*binary[[:space:]]*=/ {
            line = $0
            sub(/^[^=]*=[[:space:]]*/, "", line)
            sub(/[[:space:]]*[;#].*$/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            print line
            exit
        }
    ' "$config")

    if [ -z "$value" ]; then
        value="$DEFAULT_BINARY"
    fi

    case "$value" in
        */*|''|*[!A-Za-z0-9._+-]*)
            echo "ERROR: invalid Stratum binary name in $config: $value" >&2
            return 1
            ;;
    esac

    printf '%s\n' "$value"
}

resolve_binary_path() {
    local config="$1"
    local binary
    local binary_path

    binary=$(read_runtime_binary "$config") || return 1
    binary_path="$STRATUM_DIR/$binary"

    if [ ! -x "$binary_path" ]; then
        echo "ERROR: configured Stratum binary is not executable: $binary_path" >&2
        return 1
    fi

    printf '%s\n' "$binary_path"
}

main() {
    local resolve_only=false
    local config_input
    local config_path
    local binary_path
    local config_arg
    local coin_name
    local log_file
    local rc

    if [ "${1:-}" = "--resolve" ]; then
        resolve_only=true
        shift
    fi

    config_input="${1:-}"
    if [ -z "$config_input" ]; then
        usage
        exit 2
    fi

    config_path=$(resolve_config_path "$config_input") || {
        echo "ERROR: Stratum config not found: $config_input" >&2
        exit 2
    }

    binary_path=$(resolve_binary_path "$config_path") || exit 126

    if [ "$resolve_only" = true ]; then
        printf '%s\n' "$binary_path"
        exit 0
    fi

    coin_name="${config_path##*/}"
    coin_name="${coin_name%%.*}"
    log_file="${STRATUM_LOG_DIR}/stratum-${coin_name}.log"

    if [ ! -w "$log_file" ]; then
        echo "ERROR: Stratum log is not writable: $log_file" >&2
        echo "Run stratum_manager/install-runtime.sh to create logs and permissions." >&2
        exit 73
    fi

    ulimit -n 10240 2>/dev/null || true
    ulimit -u 10240 2>/dev/null || true

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] STRATUM_START config=${config_path##*/} binary=${binary_path##*/}"

    # YiiMP Stratum binaries expect the config relative to
    # STRATUM_DIR and without the trailing .conf extension.
    #
    # Example:
    #   resolved file : /home/crypto-data/yiimp/site/stratum/config/ltc.scrypt.conf
    #   binary arg    : config/ltc.scrypt
    config_arg="config/${config_path##*/}"
    config_arg="${config_arg%.conf}"

    while true; do
        (
            cd "$STRATUM_DIR" || exit 1
            # Keep the live GNU Screen console while persisting the exact
            # same stdout/stderr stream for post-mortem diagnostics.
            "$binary_path" "$config_arg" 2>&1 | tee -a "$log_file"
            exit "${PIPESTATUS[0]}"
        )
        rc=$?
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] STRATUM_EXIT config=${config_path##*/} binary=${binary_path##*/} exit_code=$rc restart_in=${RESTART_DELAY}s" >&2
        sleep "$RESTART_DELAY"
    done
}

main "$@"
