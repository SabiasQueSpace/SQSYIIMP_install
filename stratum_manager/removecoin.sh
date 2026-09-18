#!/usr/bin/env bash

############################################################
# SQSYIIMP Safe Coin Removal Manager
# SabiasQue.Space
############################################################

set -euo pipefail

if [[ -r /etc/yiimpool.conf ]]; then
    source /etc/yiimpool.conf
fi

STORAGE_USER="${STORAGE_USER:-crypto-data}"
STORAGE_GROUP="${STORAGE_GROUP:-${STORAGE_USER}}"
STORAGE_ROOT="${STORAGE_ROOT:-/home/${STORAGE_USER}}"

if [[ -r /etc/default/sqsyiimp ]]; then
    source /etc/default/sqsyiimp
fi

if [[ -r "$STORAGE_ROOT/yiimp/.yiimp.conf" ]]; then
    source "$STORAGE_ROOT/yiimp/.yiimp.conf"
fi

STRATUM_USER="${YIIMP_USER:-$STORAGE_USER}"
STRATUM_DIR="${PATH_STRATUM:-$STORAGE_ROOT/yiimp/site/stratum}"
CONFIG_DIR="$STRATUM_DIR/config"
SERVICE_DIR="$STRATUM_DIR/services"
MANAGED_DIR="$STRATUM_DIR/managed"
MYSQL_CNF="$STORAGE_ROOT/yiimp/.my.cnf"

MODE="check"
PURGE_NODE=false
KEEP_WALLET=false
PURGE_BACKUPS=false
PURGE_DB=false
PURGE_DB_DATA=false
ASSUME_YES=false
BACKUP_CANDIDATES=()

# Daemon shutdown safety/UX. These may be overridden through the environment.
DAEMON_RPC_TIMEOUT="${SQS_REMOVE_DAEMON_RPC_TIMEOUT:-20}"
DAEMON_STOP_TIMEOUT="${SQS_REMOVE_DAEMON_STOP_TIMEOUT:-120}"
DAEMON_TERM_TIMEOUT="${SQS_REMOVE_DAEMON_TERM_TIMEOUT:-30}"
PROGRESS_INTERVAL="${SQS_REMOVE_PROGRESS_INTERVAL:-5}"

SYMBOL=""
COIN_NAME_OVERRIDE=""
DAEMON_OVERRIDE=""
CLI_OVERRIDE=""
DATADIR_OVERRIDE=""
DAEMON_CONF_OVERRIDE=""
YIIMP_SYMBOL_OVERRIDE=""
WALLET_SYMBOL_OVERRIDE=""

usage() {
    cat <<'EOF_USAGE'
Usage:
  removecoin SYMBOL [options]

Default behavior is a dry-run. Nothing is removed unless --apply is used.

Options:
  --check                Dry-run only (default)
  --apply                Apply the planned Stratum removal
  --purge-node           Also remove the coin daemon, binaries and datadir
  --keep-wallet          With --purge-node, keep the daemon datadir/wallet
  --purge-backups        Preview and remove matching SQSYIIMP/Stratum backups
  --purge-db             Delete the YiiMP coins row only if no dependent
                         coinid/coin_id rows exist; otherwise refuse safely
  --purge-db-data        With --purge-db, back up and delete dependent YiiMP
                         coin rows, then delete the coin row. Destructive.
  --yiimp-symbol SYMBOL  YiiMP DB symbol when it differs from the managed
                         identifier (e.g. identifier cosa, DB symbol COSA)
  --wallet-symbol SYMBOL Stratum wallet/include symbol when it differs from
                         the YiiMP DB symbol (e.g. COSANTA)
  --coin-name NAME       Canonical daemon/wallet name (e.g. cosanta)
  --daemon NAME          Daemon binary basename (e.g. cosantad)
  --cli NAME             CLI binary basename (e.g. cosanta-cli)
  --datadir PATH         Daemon datadir
  --daemon-conf NAME     Daemon config basename (e.g. cosanta.conf)
  -y, --yes              Skip interactive destructive confirmation
  -h, --help             Show this help

Daemon shutdown waits:
  graceful stop          120s by default, with live elapsed-time progress
  after exact TERM       30s by default, with live elapsed-time progress

Optional environment overrides:
  SQS_REMOVE_DAEMON_RPC_TIMEOUT
  SQS_REMOVE_DAEMON_STOP_TIMEOUT
  SQS_REMOVE_DAEMON_TERM_TIMEOUT
  SQS_REMOVE_PROGRESS_INTERVAL

Examples:
  removecoin COSA
  removecoin COSA --apply
  removecoin COSA --apply --purge-node --coin-name cosanta
  removecoin COSA --apply --purge-node --purge-backups --purge-db --coin-name cosanta
  removecoin COSA --apply --purge-db --purge-db-data

Safety rules:
  * Unknown processes are never killed merely because they own a port.
  * Daemon purge is limited to explicitly resolved coin-specific binaries.
  * --purge-backups removes only the exact paths shown in the removal plan.
  * --purge-db alone refuses to continue while dependent rows exist.
  * --purge-db-data creates a SQL backup first and refuses non-zero account/market balances.
EOF_USAGE
}

log()   { printf '%s\n' "$*"; }
info()  { printf 'INFO: %s\n' "$*"; }
warn()  { printf 'WARNING: %s\n' "$*" >&2; }
fatal() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

valid_token() {
    [[ "${1:-}" =~ ^[A-Za-z0-9._-]+$ ]]
}

normalize_name() {
    printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g'
}

metadata_get() {
    local file="$1"
    local key="$2"

    [[ -r "$file" ]] || return 0

    awk -F= -v key="$key" '
        $1 == key {
            sub(/^[^=]*=/, "", $0)
            print $0
            exit
        }
    ' "$file"
}

config_value() {
    local file="$1"
    local section="$2"
    local key="$3"

    [[ -r "$file" ]] || return 0

    awk -F= -v wanted_section="$section" -v wanted_key="$key" '
        function trim(v) {
            sub(/^[[:space:]]+/, "", v)
            sub(/[[:space:]]+$/, "", v)
            return v
        }

        /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
            current=$0
            gsub(/^[[:space:]]*\[/, "", current)
            gsub(/\][[:space:]]*$/, "", current)
            current=tolower(trim(current))
            next
        }

        current == tolower(wanted_section) {
            lhs=trim($1)
            if (tolower(lhs) == tolower(wanted_key)) {
                value=$0
                sub(/^[^=]*=/, "", value)
                sub(/[[:space:]]*[;#].*$/, "", value)
                print trim(value)
                exit
            }
        }
    ' "$file"
}

read_service_config() {
    local file="$1"
    [[ -r "$file" ]] || return 0

    sed -nE \
        's/^[[:space:]]*CONFIG="([^"]+)"[[:space:]]*$/\1/p' \
        "$file" | head -n1
}

remove_cron_lines() {
    local user="$1"
    shift
    local patterns=("$@")
    local original=""
    local filtered=""
    local pattern=""

    id "$user" >/dev/null 2>&1 || return 0
    command -v crontab >/dev/null 2>&1 || return 0

    if [[ "$(id -un)" == "$user" ]]; then
        original="$(crontab -l 2>/dev/null || true)"
    else
        original="$(sudo -u "$user" crontab -l 2>/dev/null || true)"
    fi

    filtered="$original"
    for pattern in "${patterns[@]}"; do
        [[ -n "$pattern" ]] || continue
        filtered="$(printf '%s\n' "$filtered" | grep -vF "$pattern" || true)"
    done

    [[ "$filtered" == "$original" ]] && return 0

    if [[ "$(id -un)" == "$user" ]]; then
        printf '%s\n' "$filtered" | crontab -
    else
        printf '%s\n' "$filtered" | sudo -u "$user" crontab -
    fi
}

find_stratum_pids() {
    local config_name="$1"
    local alias_name="${config_name%.conf}"
    local proc=""
    local pid=""
    local owner_uid=""
    local runtime_uid=""
    local cmd=""

    runtime_uid="$(id -u "$STRATUM_USER" 2>/dev/null || true)"
    [[ -n "$runtime_uid" ]] || return 0

    for proc in /proc/[0-9]*; do
        pid="${proc#/proc/}"
        owner_uid="$(stat -c '%u' "$proc" 2>/dev/null || true)"
        [[ "$owner_uid" == "$runtime_uid" ]] || continue

        cmd="$(tr '\0' ' ' < "$proc/cmdline" 2>/dev/null || true)"
        [[ -n "$cmd" ]] || continue
        [[ "$cmd" == *stratum* ]] || continue

        if [[ "$cmd" == *"config/$config_name"* ||
              "$cmd" == *"config/$alias_name"* ||
              "$cmd" == *" $config_name "* ||
              "$cmd" == *" $alias_name "* ||
              "$cmd" == *" $config_name" ||
              "$cmd" == *" $alias_name" ]]; then
            printf '%s\n' "$pid"
        fi
    done
}

find_daemon_pids() {
    local daemon_path="$1"
    local datadir="$2"
    local expected=""
    local proc=""
    local pid=""
    local exe=""
    local cmd=""

    [[ -n "$daemon_path" ]] || return 0
    expected="$(readlink -f "$daemon_path" 2>/dev/null || printf '%s\n' "$daemon_path")"

    for proc in /proc/[0-9]*; do
        pid="${proc#/proc/}"
        exe="$(readlink "$proc/exe" 2>/dev/null || true)"
        exe="${exe% (deleted)}"
        [[ -n "$exe" ]] || continue
        exe="$(readlink -f "$exe" 2>/dev/null || printf '%s\n' "$exe")"
        [[ "$exe" == "$expected" ]] || continue

        cmd="$(tr '\0' ' ' < "$proc/cmdline" 2>/dev/null || true)"
        if [[ -n "$datadir" && "$cmd" != *"$datadir"* ]]; then
            continue
        fi

        printf '%s\n' "$pid"
    done
}

stop_stratum() {
    local wrapper="$1"
    local config_name="$2"
    local pid=""

    if [[ -x "$wrapper" ]]; then
        info "Stopping managed Stratum: $wrapper"
        "$wrapper" stop >/dev/null 2>&1 || true
        sleep 2
    fi

    while read -r pid; do
        [[ -n "$pid" ]] || continue
        warn "Stratum PID $pid remained after managed stop; sending TERM to the config-matched process"
        sudo -u "$STRATUM_USER" kill -TERM "$pid" 2>/dev/null || true
    done < <(find_stratum_pids "$config_name")

    sleep 2
}

clear_progress_line() {
    if [[ -t 1 ]]; then
        printf '\r\033[K'
    fi
}

validate_shutdown_timers() {
    local name=""
    local value=""

    for name in \
        DAEMON_RPC_TIMEOUT \
        DAEMON_STOP_TIMEOUT \
        DAEMON_TERM_TIMEOUT \
        PROGRESS_INTERVAL; do
        value="${!name}"
        if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value < 1 )); then
            fatal "$name must be a positive integer (got: $value)"
        fi
    done
}

request_daemon_stop_rpc() {
    local cli_path="$1"
    local datadir="$2"
    local conf="$3"
    local job_pid=""
    local elapsed=0
    local rc=0
    local -a spinner=('|' '/' '-' '\')
    local frame=""

    info "Requesting daemon shutdown with $cli_path (RPC timeout ${DAEMON_RPC_TIMEOUT}s)"

    if command -v timeout >/dev/null 2>&1; then
        timeout --signal=TERM --kill-after=2 "${DAEMON_RPC_TIMEOUT}s" \
            sudo -u "$STORAGE_USER" "$cli_path" \
                -datadir="$datadir" \
                -conf="$conf" \
                stop >/dev/null 2>&1 &
    else
        sudo -u "$STORAGE_USER" "$cli_path" \
            -datadir="$datadir" \
            -conf="$conf" \
            stop >/dev/null 2>&1 &
    fi
    job_pid=$!

    while kill -0 "$job_pid" 2>/dev/null; do
        if [[ -t 1 ]]; then
            frame="${spinner[$((elapsed % 4))]}"
            printf '\rINFO: Stop RPC in progress %s %ds/%ds' \
                "$frame" "$elapsed" "$DAEMON_RPC_TIMEOUT"
        elif (( elapsed == 0 || elapsed % PROGRESS_INTERVAL == 0 )); then
            info "Stop RPC in progress: ${elapsed}s/${DAEMON_RPC_TIMEOUT}s"
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    if wait "$job_pid"; then
        rc=0
    else
        rc=$?
    fi
    clear_progress_line

    if (( rc == 0 )); then
        info "Daemon stop RPC returned after ${elapsed}s; waiting for the process to flush and exit"
    elif (( rc == 124 || rc == 137 || elapsed >= DAEMON_RPC_TIMEOUT )); then
        warn "Daemon stop RPC exceeded ${DAEMON_RPC_TIMEOUT}s; continuing with process-level shutdown monitoring"
    else
        warn "Daemon stop RPC returned status $rc; continuing with process-level shutdown monitoring"
    fi
}

wait_for_daemon_exit() {
    local daemon_path="$1"
    local datadir="$2"
    local timeout_seconds="$3"
    local phase="$4"
    local elapsed=0
    local pids=""
    local -a spinner=('|' '/' '-' '\')
    local frame=""

    while :; do
        pids="$(find_daemon_pids "$daemon_path" "$datadir" | paste -sd, -)"

        if [[ -z "$pids" ]]; then
            clear_progress_line
            info "$phase complete after ${elapsed}s"
            return 0
        fi

        if (( elapsed >= timeout_seconds )); then
            clear_progress_line
            warn "$phase timed out after ${elapsed}s; daemon PID(s) still present: $pids"
            return 1
        fi

        if [[ -t 1 ]]; then
            frame="${spinner[$((elapsed % 4))]}"
            printf '\rINFO: %s %s %ds/%ds | PID(s): %s' \
                "$phase" "$frame" "$elapsed" "$timeout_seconds" "$pids"
        elif (( elapsed == 0 || elapsed % PROGRESS_INTERVAL == 0 )); then
            info "$phase: ${elapsed}s/${timeout_seconds}s | PID(s): $pids"
        fi

        sleep 1
        elapsed=$((elapsed + 1))
    done
}

stop_daemon() {
    local daemon_path="$1"
    local cli_path="$2"
    local datadir="$3"
    local conf="$4"
    local pid=""
    local initial_pids=""
    local remaining_pids=""

    initial_pids="$(find_daemon_pids "$daemon_path" "$datadir" | paste -sd, -)"
    if [[ -z "$initial_pids" ]]; then
        info "Coin daemon is already stopped"
        return 0
    fi

    info "Detected daemon PID(s): $initial_pids"

    if [[ -x "$cli_path" && -n "$datadir" && -n "$conf" ]]; then
        request_daemon_stop_rpc "$cli_path" "$datadir" "$conf"
    else
        warn "Daemon CLI/config is unavailable; skipping RPC stop and monitoring the exact daemon process"
    fi

    if wait_for_daemon_exit \
        "$daemon_path" "$datadir" "$DAEMON_STOP_TIMEOUT" \
        "Waiting for clean daemon shutdown"; then
        return 0
    fi

    while read -r pid; do
        [[ -n "$pid" ]] || continue
        warn "Daemon PID $pid did not exit within ${DAEMON_STOP_TIMEOUT}s; sending TERM to the exact daemon process"
        sudo kill -TERM "$pid" 2>/dev/null || true
    done < <(find_daemon_pids "$daemon_path" "$datadir")

    if wait_for_daemon_exit \
        "$daemon_path" "$datadir" "$DAEMON_TERM_TIMEOUT" \
        "Waiting after TERM"; then
        return 0
    fi

    remaining_pids="$(find_daemon_pids "$daemon_path" "$datadir" | paste -sd, -)"
    fatal "Coin daemon is still running (PID(s): ${remaining_pids:-unknown}); refusing to delete binaries or datadir. No SIGKILL is sent automatically."
}

remove_binary_and_aliases() {
    local path="$1"
    local real=""
    local candidate=""
    local target=""

    [[ -n "$path" ]] || return 0
    [[ -e "$path" || -L "$path" ]] || return 0

    real="$(readlink -f "$path" 2>/dev/null || true)"

    if [[ -n "$real" ]]; then
        shopt -s nullglob
        for candidate in /usr/bin/* /usr/local/bin/*; do
            [[ -L "$candidate" ]] || continue
            target="$(readlink -f "$candidate" 2>/dev/null || true)"
            [[ "$target" == "$real" ]] || continue
            info "Removing compatibility symlink: $candidate"
            sudo rm -f -- "$candidate"
        done
        shopt -u nullglob
    fi

    if [[ -e "$path" || -L "$path" ]]; then
        info "Removing binary: $path"
        sudo rm -f -- "$path"
    fi
}

remove_exact_wallet_exclude() {
    local file="$1"
    local symbol="$2"
    local tmp=""

    [[ -f "$file" ]] || return 0

    if ! grep -Fqx "exclude = $symbol" "$file"; then
        return 0
    fi

    tmp="$(mktemp)"
    awk -v wanted="exclude = $symbol" '$0 != wanted { print }' "$file" > "$tmp"
    sudo install --mode="$(stat -c '%a' "$file")" \
        --owner="$(stat -c '%U' "$file")" \
        --group="$(stat -c '%G' "$file")" \
        "$tmp" "$file"
    rm -f "$tmp"
}

mysql_cnf_value() {
    local file="$1"
    local section="$2"
    local key="$3"
    local value=""

    [[ -r "$file" ]] || return 0

    value="$(awk -F= -v wanted_section="$section" -v wanted_key="$key" '
        function trim(v) {
            sub(/^[[:space:]]+/, "", v)
            sub(/[[:space:]]+$/, "", v)
            return v
        }

        /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
            current=$0
            gsub(/^[[:space:]]*\[/, "", current)
            gsub(/\][[:space:]]*$/, "", current)
            current=tolower(trim(current))
            next
        }

        current == tolower(wanted_section) {
            lhs=tolower(trim($1))
            if (lhs == tolower(wanted_key)) {
                value=$0
                sub(/^[^=]*=/, "", value)
                print trim(value)
                exit
            }
        }
    ' "$file")"

    value="${value#\"}"
    value="${value%\"}"
    value="${value#\'}"
    value="${value%\'}"
    printf '%s\n' "$value"
}

resolve_yiimp_db_name() {
    local db="${YiiMPDBName:-${YIIMP_DBNAME:-}}"
    local php_config="$STORAGE_ROOT/yiimp/site/web/yaamp/defaultconfig.php"

    if [[ -z "$db" ]]; then
        db="$(mysql_cnf_value "$MYSQL_CNF" clienthost1 database)"
    fi

    if [[ -z "$db" ]]; then
        db="$(mysql_cnf_value "$MYSQL_CNF" client database)"
    fi

    if [[ -z "$db" && -r "$php_config" ]]; then
        db="$(sed -nE \
            "s/^[[:space:]]*define\\(['\\\"]YIIMP_DBNAME['\\\"][[:space:]]*,[[:space:]]*['\\\"]([^'\\\"]+)['\\\"]\\)[[:space:]]*;.*$/\\1/p" \
            "$php_config" | head -n1)"
    fi

    # SELECT DATABASE() returns the literal string NULL when credentials are
    # valid but no default schema is selected. Never treat that as a DB name.
    [[ "$db" != "NULL" ]] || db=""
    printf '%s\n' "$db"
}

resolve_db_client() {
    if command -v mariadb >/dev/null 2>&1; then
        command -v mariadb
    elif command -v mysql >/dev/null 2>&1; then
        command -v mysql
    else
        return 1
    fi
}

resolve_db_dump_client() {
    if command -v mariadb-dump >/dev/null 2>&1; then
        command -v mariadb-dump
    elif command -v mysqldump >/dev/null 2>&1; then
        command -v mysqldump
    else
        return 1
    fi
}

quote_sql_ident() {
    printf '%s' "$1" | sed 's/`/``/g'
}

backup_and_purge_db_dependencies() {
    local db="$1"
    local db_client="$2"
    local coin_id="$3"
    shift 3
    local -a dependencies=("$@")
    local dump_client=""
    local backup_dir="$STORAGE_ROOT/yiimp/backups/removecoin-db"
    local backup_file=""
    local timestamp=""
    local entry="" table="" columns_csv="" where_clause="" column=""
    local table_q="" column_q=""
    local nonzero=""

    dump_client="$(resolve_db_dump_client || true)"
    [[ -n "$dump_client" ]] || fatal "mariadb-dump/mysqldump is required for --purge-db-data"

    # Financial safety: never silently destroy a spendable user/market balance.
    if $db_client --defaults-extra-file="$MYSQL_CNF" --database="$db" --batch --skip-column-names \
        -e "SHOW COLUMNS FROM accounts LIKE 'balance';" 2>/dev/null | grep -q .; then
        nonzero="$($db_client --defaults-extra-file="$MYSQL_CNF" --database="$db" --batch --skip-column-names \
            -e "SELECT COUNT(*) FROM accounts WHERE coinid=$coin_id AND ABS(COALESCE(balance,0)) > 0.000000000001;" 2>/dev/null | head -n1 || true)"
        [[ "${nonzero:-0}" == "0" ]] || fatal "Refusing --purge-db-data: accounts contains $nonzero non-zero balance row(s) for coin id $coin_id"
    fi

    if $db_client --defaults-extra-file="$MYSQL_CNF" --database="$db" --batch --skip-column-names \
        -e "SHOW TABLES LIKE 'markets';" 2>/dev/null | grep -qx 'markets'; then
        nonzero="$($db_client --defaults-extra-file="$MYSQL_CNF" --database="$db" --batch --skip-column-names \
            -e "SELECT COUNT(*) FROM markets WHERE coinid=$coin_id AND (ABS(COALESCE(balance,0)) > 0.000000000001 OR ABS(COALESCE(ontrade,0)) > 0.000000000001);" 2>/dev/null | head -n1 || true)"
        [[ "${nonzero:-0}" == "0" ]] || fatal "Refusing --purge-db-data: markets contains $nonzero non-zero balance/ontrade row(s) for coin id $coin_id"
    fi

    timestamp="$(date +%Y%m%d-%H%M%S)"
    sudo mkdir -p "$backup_dir"
    sudo chmod 0750 "$backup_dir"
    backup_file="$backup_dir/${YIIMP_SYMBOL_UPPER}-coinid-${coin_id}-${timestamp}.sql"
    sudo touch "$backup_file"
    sudo chmod 0600 "$backup_file"

    info "Creating automatic YiiMP row backup: $backup_file"

    sudo "$dump_client" --defaults-extra-file="$MYSQL_CNF" \
        --no-create-info --skip-triggers "$db" coins --where="id=$coin_id" \
        > "$backup_file"

    for entry in "${dependencies[@]}"; do
        table="${entry%%:*}"
        columns_csv="${entry#*:}"
        [[ -n "$table" && -n "$columns_csv" ]] || continue

        where_clause=""
        IFS=',' read -r -a dep_columns <<< "$columns_csv"
        for column in "${dep_columns[@]}"; do
            [[ -n "$column" ]] || continue
            column_q="$(quote_sql_ident "$column")"
            if [[ -n "$where_clause" ]]; then
                where_clause+=" OR "
            fi
            where_clause+="\`$column_q\`=$coin_id"
        done
        [[ -n "$where_clause" ]] || continue

        sudo "$dump_client" --defaults-extra-file="$MYSQL_CNF" \
            --no-create-info --skip-triggers "$db" "$table" --where="$where_clause" \
            >> "$backup_file"
    done

    if $db_client --defaults-extra-file="$MYSQL_CNF" --database="$db" --batch --skip-column-names \
        -e "SHOW TABLES LIKE 'coin_daemon_config';" 2>/dev/null | grep -qx 'coin_daemon_config'; then
        sudo "$dump_client" --defaults-extra-file="$MYSQL_CNF" \
            --no-create-info --skip-triggers "$db" coin_daemon_config --where="coin_id=$coin_id" \
            >> "$backup_file"
    fi

    [[ -s "$backup_file" ]] || fatal "Automatic YiiMP backup is empty; refusing destructive DB purge"
    info "Automatic YiiMP backup created ($(du -h "$backup_file" | awk '{print $1}'))"

    if [[ "$ASSUME_YES" != true ]]; then
        echo
        read -r -p "Type PURGE $YIIMP_SYMBOL_UPPER to delete dependent YiiMP rows: " purge_confirmation
        [[ "$purge_confirmation" == "PURGE $YIIMP_SYMBOL_UPPER" ]] || fatal "Database purge confirmation did not match; backup kept at $backup_file"
    fi

    info "Deleting dependent YiiMP rows for coin id $coin_id"
    for entry in "${dependencies[@]}"; do
        table="${entry%%:*}"
        columns_csv="${entry#*:}"
        [[ -n "$table" && -n "$columns_csv" ]] || continue

        where_clause=""
        IFS=',' read -r -a dep_columns <<< "$columns_csv"
        for column in "${dep_columns[@]}"; do
            [[ -n "$column" ]] || continue
            column_q="$(quote_sql_ident "$column")"
            if [[ -n "$where_clause" ]]; then
                where_clause+=" OR "
            fi
            where_clause+="\`$column_q\`=$coin_id"
        done
        [[ -n "$where_clause" ]] || continue

        table_q="$(quote_sql_ident "$table")"
        $db_client --defaults-extra-file="$MYSQL_CNF" --database="$db" \
            -e "DELETE FROM \`$table_q\` WHERE $where_clause;"
    done

    info "Dependent YiiMP rows removed; backup retained at $backup_file"
}

purge_db_safely() {
    local db=""
    local db_client=""
    local selected_db=""
    local coin_id=""
    local refs=0
    local table=""
    local column=""
    local count=""
    local symbol_sql=""
    local db_sql=""
    local -a dependency_entries=()
    local -A dependency_columns=()
    local dep_entry=""

    [[ -r "$MYSQL_CNF" ]] || fatal "YiiMP MariaDB client config not found: $MYSQL_CNF"

    db_client="$(resolve_db_client || true)"
    [[ -n "$db_client" ]] || fatal "mariadb/mysql client is required for --purge-db"

    db="$(resolve_yiimp_db_name)"
    [[ -n "$db" ]] || fatal "Unable to determine YiiMP database name from .yiimp.conf, $MYSQL_CNF or defaultconfig.php"
    [[ "$db" =~ ^[A-Za-z0-9_.-]+$ ]] || fatal "Unsafe YiiMP database name resolved: $db"

    info "YiiMP DB target: $db (client: ${db_client##*/})"

    selected_db="$($db_client --defaults-extra-file="$MYSQL_CNF" \
        --database="$db" --batch --skip-column-names \
        -e 'SELECT DATABASE();' 2>/dev/null | head -n1 || true)"

    [[ "$selected_db" == "$db" ]] || \
        fatal "Unable to select YiiMP database '$db' with $MYSQL_CNF"

    if ! $db_client --defaults-extra-file="$MYSQL_CNF" \
        --database="$db" --batch --skip-column-names \
        -e "SHOW TABLES LIKE 'coins';" 2>/dev/null | grep -qx 'coins'; then
        fatal "YiiMP database '$db' does not contain the coins table"
    fi

    symbol_sql="$(printf '%s' "$YIIMP_SYMBOL_UPPER" | sed "s/'/''/g")"
    db_sql="$(printf '%s' "$db" | sed "s/'/''/g")"

    coin_id="$($db_client --defaults-extra-file="$MYSQL_CNF" \
        --database="$db" --batch --skip-column-names \
        -e "SELECT id FROM coins WHERE UPPER(symbol)=UPPER('$symbol_sql') LIMIT 1;" \
        | head -n1)"

    if [[ -z "$coin_id" ]]; then
        info "YiiMP DB: coin symbol $YIIMP_SYMBOL_UPPER is already absent"
        return 0
    fi

    [[ "$coin_id" =~ ^[0-9]+$ ]] || fatal "Unexpected YiiMP coin id: $coin_id"
    info "YiiMP DB coin id: $coin_id"
    info "Checking dependent coinid/coin_id rows before deletion..."

    while IFS=$'\t' read -r table column; do
        [[ -n "$table" && -n "$column" ]] || continue
        [[ "$table" == "coins" ]] && continue
        [[ "$table" == "coin_daemon_config" ]] && continue

        count="$($db_client --defaults-extra-file="$MYSQL_CNF" \
            --database="$db" --batch --skip-column-names \
            -e "SELECT COUNT(*) FROM \`$table\` WHERE \`$column\`=$coin_id;" \
            2>/dev/null | head -n1 || true)"
        count="${count:-0}"

        if [[ "$count" =~ ^[0-9]+$ ]] && (( count > 0 )); then
            printf '  %-36s %-12s %s row(s)\n' "$table" "$column" "$count"
            refs=$((refs + count))
            if [[ -n "${dependency_columns[$table]:-}" ]]; then
                dependency_columns[$table]+=",$column"
            else
                dependency_columns[$table]="$column"
            fi
        fi
    done < <(
        $db_client --defaults-extra-file="$MYSQL_CNF" \
            --database="$db" --batch --skip-column-names \
            -e "SELECT TABLE_NAME,COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='$db_sql' AND COLUMN_NAME IN ('coinid','coin_id') ORDER BY TABLE_NAME;"
    )

    if (( refs > 0 )); then
        if [[ "$PURGE_DB_DATA" != true ]]; then
            fatal "YiiMP DB still contains $refs dependent row(s); coin row was NOT deleted. Re-run with --purge-db-data only if those rows should be permanently removed."
        fi

        for table in "${!dependency_columns[@]}"; do
            dependency_entries+=("$table:${dependency_columns[$table]}")
        done
        backup_and_purge_db_dependencies "$db" "$db_client" "$coin_id" "${dependency_entries[@]}"
    elif [[ "$PURGE_DB_DATA" == true ]]; then
        info "YiiMP DB has no dependent coinid/coin_id rows; --purge-db-data has nothing extra to remove"
    fi

    if $db_client --defaults-extra-file="$MYSQL_CNF" \
        --database="$db" --batch --skip-column-names \
        -e "SHOW TABLES LIKE 'coin_daemon_config';" | grep -qx 'coin_daemon_config'; then
        $db_client --defaults-extra-file="$MYSQL_CNF" \
            --database="$db" \
            -e "DELETE FROM coin_daemon_config WHERE coin_id=$coin_id;"
    fi

    $db_client --defaults-extra-file="$MYSQL_CNF" \
        --database="$db" \
        -e "DELETE FROM coins WHERE id=$coin_id LIMIT 1;"

    info "YiiMP DB coin row removed: $YIIMP_SYMBOL_UPPER (id=$coin_id)"
}

backup_token_match() {
    local value="${1:-}"
    local token="${2:-}"

    [[ -n "$token" ]] || return 1

    value="${value,,}"
    token="${token,,}"
    value="${value//./-}"
    value="${value//_/-}"
    token="${token//./-}"
    token="${token//_/-}"

    [[ "-$value-" == *-"$token"-* ]]
}

backup_name_matches_coin() {
    local lower="${1,,}"

    backup_token_match "$lower" "$SYMBOL_LOWER" ||
        backup_token_match "$lower" "$COIN_NAME" ||
        backup_token_match "$lower" "${YIIMP_SYMBOL_UPPER,,}" ||
        backup_token_match "$lower" "${WALLET_SYMBOL_UPPER,,}"
}

collect_backup_candidates() {
    local path=""
    local base=""
    local lower=""
    local backup_root="$STORAGE_ROOT/yiimp/backups"
    local protected_db_backup="$backup_root/removecoin-db"

    {
        while IFS= read -r -d '' path; do
            base="${path##*/}"
            lower="${base,,}"

            case "$lower" in
                *backup*|*.bak|*.bak-*|*.old|*.old-*|*.orig|*.orig-*) ;;
                *) continue ;;
            esac

            if backup_name_matches_coin "$lower"; then
                printf '%s\0' "$path"
            fi
        done < <(
            find "$CONFIG_DIR" "$SERVICE_DIR" \
                -maxdepth 1 \
                -mindepth 1 \
                -print0 2>/dev/null || true
        )

        if [[ -d "$backup_root" ]]; then
            while IFS= read -r -d '' path; do
                [[ "$path" == "$protected_db_backup" ]] && continue

                base="${path##*/}"
                lower="${base,,}"

                if backup_name_matches_coin "$lower"; then
                    printf '%s\0' "$path"
                fi
            done < <(
                find "$backup_root" \
                    -maxdepth 1 \
                    -mindepth 1 \
                    -print0 2>/dev/null || true
            )
        fi
    } | sort -zu
}

load_backup_candidates() {
    local path=""
    BACKUP_CANDIDATES=()

    while IFS= read -r -d '' path; do
        BACKUP_CANDIDATES+=("$path")
    done < <(collect_backup_candidates)
}

backup_path_size_bytes() {
    local path="$1"
    local bytes=""

    bytes="$(du -sb -- "$path" 2>/dev/null | awk 'NR==1 {print $1}' || true)"
    if [[ "$bytes" =~ ^[0-9]+$ ]]; then
        printf '%s' "$bytes"
    else
        printf '0'
    fi
}

format_bytes() {
    local bytes="${1:-0}"

    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec-i --suffix=B "$bytes" 2>/dev/null || printf '%sB' "$bytes"
    else
        printf '%sB' "$bytes"
    fi
}

preview_backup_candidates() {
    local path=""
    local bytes=0
    local total_bytes=0
    local size=""

    log "Backup matches  : ${#BACKUP_CANDIDATES[@]}"

    if ((${#BACKUP_CANDIDATES[@]} == 0)); then
        log "Backup size     : 0B"
        return 0
    fi

    log "Backup candidates:"
    for path in "${BACKUP_CANDIDATES[@]}"; do
        bytes="$(backup_path_size_bytes "$path")"
        total_bytes=$((total_bytes + bytes))
        size="$(format_bytes "$bytes")"
        printf '  %-9s %s\n' "[$size]" "$path"
    done

    log "Backup size     : $(format_bytes "$total_bytes")"
    log "DB safety backup: $STORAGE_ROOT/yiimp/backups/removecoin-db/ (protected)"
}

remove_backups() {
    local path=""
    local removed=0

    for path in "${BACKUP_CANDIDATES[@]}"; do
        if [[ -e "$path" || -L "$path" ]]; then
            info "Removing backup: $path"
            sudo rm -rf -- "$path"
            removed=$((removed + 1))
        fi
    done

    if ((removed == 0)); then
        info "No matching backups were present at apply time"
    else
        info "Removed $removed planned backup path(s)"
    fi
}

# ------------------------------------------------------------
# Argument parsing
# ------------------------------------------------------------

while (($#)); do
    case "$1" in
        --check)
            MODE="check"
            ;;
        --apply)
            MODE="apply"
            ;;
        --purge-node)
            PURGE_NODE=true
            ;;
        --keep-wallet)
            KEEP_WALLET=true
            ;;
        --purge-backups)
            PURGE_BACKUPS=true
            ;;
        --purge-db)
            PURGE_DB=true
            ;;
        --purge-db-data)
            PURGE_DB=true
            PURGE_DB_DATA=true
            ;;
        --yiimp-symbol)
            shift
            (($#)) || fatal "--yiimp-symbol requires a value"
            YIIMP_SYMBOL_OVERRIDE="$1"
            ;;
        --wallet-symbol)
            shift
            (($#)) || fatal "--wallet-symbol requires a value"
            WALLET_SYMBOL_OVERRIDE="$1"
            ;;
        --coin-name)
            shift
            (($#)) || fatal "--coin-name requires a value"
            COIN_NAME_OVERRIDE="$1"
            ;;
        --daemon)
            shift
            (($#)) || fatal "--daemon requires a value"
            DAEMON_OVERRIDE="$1"
            ;;
        --cli)
            shift
            (($#)) || fatal "--cli requires a value"
            CLI_OVERRIDE="$1"
            ;;
        --datadir)
            shift
            (($#)) || fatal "--datadir requires a value"
            DATADIR_OVERRIDE="$1"
            ;;
        --daemon-conf)
            shift
            (($#)) || fatal "--daemon-conf requires a value"
            DAEMON_CONF_OVERRIDE="$1"
            ;;
        -y|--yes)
            ASSUME_YES=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --*)
            fatal "Unknown option: $1"
            ;;
        *)
            [[ -z "$SYMBOL" ]] || fatal "Only one coin symbol may be supplied"
            SYMBOL="$1"
            ;;
    esac
    shift
done

validate_shutdown_timers

[[ -n "$SYMBOL" ]] || { usage; exit 1; }
valid_token "$SYMBOL" || fatal "Invalid coin symbol: $SYMBOL"

SYMBOL_UPPER="${SYMBOL^^}"
SYMBOL_LOWER="${SYMBOL,,}"
METADATA_FILE="$MANAGED_DIR/${SYMBOL_LOWER}.conf"

YIIMP_SYMBOL="${YIIMP_SYMBOL_OVERRIDE:-$(metadata_get "$METADATA_FILE" SYMBOL)}"
YIIMP_SYMBOL="${YIIMP_SYMBOL:-$SYMBOL_UPPER}"
valid_token "$YIIMP_SYMBOL" || fatal "Invalid YiiMP symbol: $YIIMP_SYMBOL"
YIIMP_SYMBOL_UPPER="${YIIMP_SYMBOL^^}"

WALLET_SYMBOL="${WALLET_SYMBOL_OVERRIDE:-$(metadata_get "$METADATA_FILE" WALLET_SYMBOL)}"
WALLET_SYMBOL="${WALLET_SYMBOL:-$YIIMP_SYMBOL_UPPER}"
valid_token "$WALLET_SYMBOL" || fatal "Invalid Stratum wallet symbol: $WALLET_SYMBOL"
WALLET_SYMBOL_UPPER="${WALLET_SYMBOL^^}"

SERVICE_FILE="$SERVICE_DIR/${SYMBOL_LOWER}.sh"
WRAPPER="/usr/bin/stratum.${SYMBOL_LOWER}"
COMPAT_WRAPPER="/usr/bin/sqs-stratum-${SYMBOL_LOWER}"
LEGACY_CONTROL="$CONFIG_DIR/stratum.${SYMBOL_LOWER}"

CONFIG_NAME="$(metadata_get "$METADATA_FILE" STRATUM_CONFIG)"
if [[ -z "$CONFIG_NAME" ]]; then
    CONFIG_NAME="$(read_service_config "$SERVICE_FILE")"
fi
if [[ -z "$CONFIG_NAME" && -r "$WRAPPER" ]]; then
    CONFIG_NAME="$(read_service_config "$WRAPPER")"
fi
if [[ -z "$CONFIG_NAME" ]]; then
    mapfile -t candidates < <(
        find "$CONFIG_DIR" -maxdepth 1 -type f \
            -name "${SYMBOL_LOWER}.*.conf" \
            ! -name '*.backup-*' \
            ! -name '*.bak*' \
            -printf '%f\n' 2>/dev/null || true
    )
    if ((${#candidates[@]} == 1)); then
        CONFIG_NAME="${candidates[0]}"
    elif ((${#candidates[@]} > 1)); then
        fatal "Multiple active configs found for $SYMBOL_UPPER; metadata/service resolution is required"
    fi
fi

CONFIG_PATH=""
CONFIG_ALIAS=""
ALGO="$(metadata_get "$METADATA_FILE" ALGO)"
PORT="$(metadata_get "$METADATA_FILE" PORT)"
STRATUM_BINARY="$(metadata_get "$METADATA_FILE" STRATUM_BINARY)"

if [[ -n "$CONFIG_NAME" ]]; then
    valid_token "$CONFIG_NAME" || fatal "Unsafe config name resolved: $CONFIG_NAME"
    CONFIG_PATH="$CONFIG_DIR/$CONFIG_NAME"
    CONFIG_ALIAS="$CONFIG_DIR/${CONFIG_NAME%.conf}"
    [[ -n "$ALGO" ]] || ALGO="$(config_value "$CONFIG_PATH" STRATUM algo)"
    [[ -n "$PORT" ]] || PORT="$(config_value "$CONFIG_PATH" TCP port)"
    [[ -n "$STRATUM_BINARY" ]] || STRATUM_BINARY="$(config_value "$CONFIG_PATH" RUNTIME binary)"
fi

COIN_NAME="${COIN_NAME_OVERRIDE:-$(metadata_get "$METADATA_FILE" COIN_NAME)}"
COIN_NAME="$(normalize_name "$COIN_NAME")"

NODE_TYPE="$(metadata_get "$METADATA_FILE" NODE_TYPE)"
NODE_TYPE="${NODE_TYPE:-utxo}"
DAEMON_BINARY="${DAEMON_OVERRIDE:-$(metadata_get "$METADATA_FILE" DAEMON_BINARY)}"
CLI_BINARY="${CLI_OVERRIDE:-$(metadata_get "$METADATA_FILE" CLI_BINARY)}"
TX_BINARY="$(metadata_get "$METADATA_FILE" TX_BINARY)"
UTIL_BINARY="$(metadata_get "$METADATA_FILE" UTIL_BINARY)"
HASH_BINARY="$(metadata_get "$METADATA_FILE" HASH_BINARY)"
WALLET_BINARY="$(metadata_get "$METADATA_FILE" WALLET_BINARY)"
QT_BINARY="$(metadata_get "$METADATA_FILE" QT_BINARY)"
DAEMON_DATADIR="${DATADIR_OVERRIDE:-$(metadata_get "$METADATA_FILE" DAEMON_DATADIR)}"
DAEMON_CONF="${DAEMON_CONF_OVERRIDE:-$(metadata_get "$METADATA_FILE" DAEMON_CONF)}"
DAEMON_BOOT_LOG="$(metadata_get "$METADATA_FILE" DAEMON_BOOT_LOG)"
DAEMON_SERVICE="$(metadata_get "$METADATA_FILE" DAEMON_SERVICE)"
DAEMON_SERVICE_FILE="$(metadata_get "$METADATA_FILE" DAEMON_SERVICE_FILE)"
DAEMON_RUNNER="$(metadata_get "$METADATA_FILE" DAEMON_RUNNER)"
DAEMON_RPC_PORT="$(metadata_get "$METADATA_FILE" DAEMON_RPC_PORT)"
DAEMON_RPC_URL="$(metadata_get "$METADATA_FILE" DAEMON_RPC_URL)"
DAEMON_P2P_PORT="$(metadata_get "$METADATA_FILE" DAEMON_P2P_PORT)"
RPC_HELPER_BINARY="$(metadata_get "$METADATA_FILE" RPC_HELPER_BINARY)"

if [[ "$PURGE_NODE" == true ]]; then
    if [[ -z "$COIN_NAME" ]]; then
        fatal "--purge-node requires managed daemon metadata or --coin-name NAME"
    fi

    if [[ "$NODE_TYPE" == "evm" ]]; then
        [[ -n "$DAEMON_BINARY" ]] || fatal "EVM node metadata is missing DAEMON_BINARY"
        valid_token "$DAEMON_BINARY" || fatal "Unsafe daemon binary name: $DAEMON_BINARY"
        [[ -z "$RPC_HELPER_BINARY" ]] || valid_token "$RPC_HELPER_BINARY" || fatal "Unsafe RPC helper name: $RPC_HELPER_BINARY"
        [[ -n "$DAEMON_DATADIR" && "$DAEMON_DATADIR" == /* ]] || fatal "EVM daemon datadir must be an absolute path"
        [[ -n "$DAEMON_SERVICE" ]] || fatal "EVM node metadata is missing DAEMON_SERVICE"
        [[ "$DAEMON_SERVICE" =~ ^[A-Za-z0-9@._-]+\.service$ ]] || fatal "Unsafe systemd service name: $DAEMON_SERVICE"
        [[ -n "$DAEMON_SERVICE_FILE" ]] || DAEMON_SERVICE_FILE="/etc/systemd/system/$DAEMON_SERVICE"
        case "$DAEMON_SERVICE_FILE" in
            /etc/systemd/system/sqsyiimp-*.service) ;;
            *) fatal "Refusing unsafe EVM service path: $DAEMON_SERVICE_FILE" ;;
        esac
        if [[ -n "$DAEMON_RUNNER" ]]; then
            case "$DAEMON_RUNNER" in
                /usr/local/lib/sqsyiimp/*) ;;
                *) fatal "Refusing unsafe EVM runner path: $DAEMON_RUNNER" ;;
            esac
        fi
    else
        DAEMON_BINARY="${DAEMON_BINARY:-${COIN_NAME}d}"
        CLI_BINARY="${CLI_BINARY:-${COIN_NAME}-cli}"
        TX_BINARY="${TX_BINARY:-${COIN_NAME}-tx}"
        UTIL_BINARY="${UTIL_BINARY:-${COIN_NAME}-util}"
        HASH_BINARY="${HASH_BINARY:-${COIN_NAME}-hash}"
        WALLET_BINARY="${WALLET_BINARY:-${COIN_NAME}-wallet}"
        QT_BINARY="${QT_BINARY:-${COIN_NAME}-qt}"
        DAEMON_DATADIR="${DAEMON_DATADIR:-$STORAGE_ROOT/wallets/.${COIN_NAME}}"
        DAEMON_CONF="${DAEMON_CONF:-${COIN_NAME}.conf}"
        DAEMON_BOOT_LOG="${DAEMON_BOOT_LOG:-/var/log/${COIN_NAME}-daemon-boot.log}"

        for binary_name in "$DAEMON_BINARY" "$CLI_BINARY" "$TX_BINARY" "$UTIL_BINARY" "$HASH_BINARY" "$WALLET_BINARY" "$QT_BINARY"; do
            [[ -z "$binary_name" ]] || valid_token "$binary_name" || fatal "Unsafe binary name: $binary_name"
        done

        [[ "$DAEMON_DATADIR" == /* ]] || fatal "Daemon datadir must be an absolute path"
        valid_token "$DAEMON_CONF" || fatal "Unsafe daemon config name: $DAEMON_CONF"
    fi
fi

# ------------------------------------------------------------
# Plan
# ------------------------------------------------------------

log "===================================================="
log " SQSYIIMP Safe Coin Removal"
log "===================================================="
log "Symbol          : $SYMBOL_UPPER"
log "Identifier      : $SYMBOL_LOWER"
log "YiiMP symbol     : $YIIMP_SYMBOL_UPPER"
log "Wallet symbol    : $WALLET_SYMBOL_UPPER"
log "Mode            : $MODE"
log "Metadata        : ${METADATA_FILE}$( [[ -f "$METADATA_FILE" ]] && printf ' (found)' || printf ' (not found)' )"
log "Algorithm       : ${ALGO:-unknown}"
log "Port            : ${PORT:-unknown}"
log "Stratum config  : ${CONFIG_PATH:-not resolved}"
log "Stratum alias   : ${CONFIG_ALIAS:-not resolved}"
log "Service         : $SERVICE_FILE"
log "Wrapper         : $WRAPPER"
log "Stratum binary  : ${STRATUM_BINARY:-unknown}"
log "Stratum log     : /var/log/stratum-${SYMBOL_LOWER}.log"
log ""
log "Purge node      : $PURGE_NODE"
if [[ "$PURGE_NODE" == true ]]; then
    log "Coin name       : $COIN_NAME"
    log "Node type       : $NODE_TYPE"
    log "Daemon          : /usr/bin/$DAEMON_BINARY"
    if [[ "$NODE_TYPE" == "evm" ]]; then
        log "Service         : ${DAEMON_SERVICE:-unknown}"
        log "RPC             : ${DAEMON_RPC_URL:-unknown}"
        log "P2P port        : ${DAEMON_P2P_PORT:-unknown}"
    else
        log "CLI             : /usr/bin/$CLI_BINARY"
        log "Daemon conf     : $DAEMON_CONF"
        log "Shutdown wait   : ${DAEMON_STOP_TIMEOUT}s graceful + ${DAEMON_TERM_TIMEOUT}s after TERM"
    fi
    log "Datadir         : $DAEMON_DATADIR"
    log "Keep wallet     : $KEEP_WALLET"
fi
log "Purge backups   : $PURGE_BACKUPS"
if [[ "$PURGE_BACKUPS" == true ]]; then
    load_backup_candidates
    preview_backup_candidates
fi
log "Purge DB        : $PURGE_DB"
log "Purge DB data   : $PURGE_DB_DATA"
if [[ "$PURGE_DB" == true ]]; then
    DB_PREVIEW="$(resolve_yiimp_db_name)"
    DB_CLIENT_PREVIEW="$(resolve_db_client 2>/dev/null || true)"
    log "DB target       : ${DB_PREVIEW:-unresolved}"
    log "DB client       : ${DB_CLIENT_PREVIEW##*/}"
fi
log "===================================================="

if [[ "$MODE" == "check" ]]; then
    echo
    info "Dry-run complete. Nothing was changed."
    echo
    echo "To apply the requested operation:"
    printf '  sudo removecoin %q --apply' "$SYMBOL_UPPER"
    [[ "$PURGE_NODE" == true ]] && printf ' --purge-node'
    [[ "$KEEP_WALLET" == true ]] && printf ' --keep-wallet'
    [[ "$PURGE_BACKUPS" == true ]] && printf ' --purge-backups'
    [[ "$PURGE_DB" == true ]] && printf ' --purge-db'
    [[ "$PURGE_DB_DATA" == true ]] && printf ' --purge-db-data'
    [[ "$YIIMP_SYMBOL_UPPER" != "$SYMBOL_UPPER" ]] && printf ' --yiimp-symbol %q' "$YIIMP_SYMBOL_UPPER"
    [[ "$WALLET_SYMBOL_UPPER" != "$YIIMP_SYMBOL_UPPER" ]] && printf ' --wallet-symbol %q' "$WALLET_SYMBOL_UPPER"
    [[ -n "$COIN_NAME" && "$PURGE_NODE" == true ]] && printf ' --coin-name %q' "$COIN_NAME"
    printf '\n'
    exit 0
fi

if [[ "$PURGE_NODE" == true && "$KEEP_WALLET" == false ]]; then
    warn "--purge-node will permanently delete the daemon datadir: $DAEMON_DATADIR"
    warn "This may contain wallet.dat, keys and the complete blockchain."
fi

if [[ "$PURGE_DB_DATA" == true ]]; then
    warn "--purge-db-data will permanently delete YiiMP rows that reference coin $YIIMP_SYMBOL_UPPER after creating an automatic SQL backup."
fi

if [[ "$ASSUME_YES" != true ]]; then
    if [[ ! -t 0 ]]; then
        fatal "Destructive non-interactive execution requires --yes"
    fi

    echo
    read -r -p "Type $SYMBOL_UPPER to confirm removal: " confirmation
    [[ "$confirmation" == "$SYMBOL_UPPER" ]] || fatal "Confirmation did not match; nothing was removed"
fi

# ------------------------------------------------------------
# Apply Stratum removal
# ------------------------------------------------------------

if [[ -n "$CONFIG_NAME" ]]; then
    stop_stratum "$WRAPPER" "$CONFIG_NAME"
elif [[ -x "$WRAPPER" ]]; then
    info "Stopping managed Stratum wrapper"
    "$WRAPPER" stop >/dev/null 2>&1 || true
    sleep 2
fi

remove_cron_lines "$STRATUM_USER" \
    "/usr/bin/stratum.${SYMBOL_LOWER} start" \
    "sqs-stratum-${SYMBOL_LOWER} start"

if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" && "${SUDO_USER}" != "$STRATUM_USER" ]]; then
    remove_cron_lines "$SUDO_USER" \
        "/usr/bin/stratum.${SYMBOL_LOWER} start" \
        "sqs-stratum-${SYMBOL_LOWER} start"
fi

if [[ -n "$PORT" && "$PORT" =~ ^[0-9]+$ ]] && command -v ufw >/dev/null 2>&1; then
    if sudo ufw status 2>/dev/null | grep -Eq "^[[:space:]]*${PORT}([/[:space:]]|$)"; then
        info "Removing UFW rule for Stratum port $PORT"
        sudo ufw --force delete allow "$PORT" >/dev/null 2>&1 || \
            warn "Could not remove UFW rule for port $PORT"
    fi
fi

for path in "$SERVICE_FILE" "$WRAPPER" "$COMPAT_WRAPPER" "$LEGACY_CONTROL"; do
    if [[ -e "$path" || -L "$path" ]]; then
        info "Removing Stratum control: $path"
        sudo rm -f -- "$path"
    fi
done

if [[ -n "$CONFIG_PATH" && ( -e "$CONFIG_PATH" || -L "$CONFIG_PATH" ) ]]; then
    info "Removing Stratum config: $CONFIG_PATH"
    sudo rm -f -- "$CONFIG_PATH"
fi

if [[ -n "$CONFIG_ALIAS" && ( -e "$CONFIG_ALIAS" || -L "$CONFIG_ALIAS" ) ]]; then
    info "Removing Stratum compatibility config: $CONFIG_ALIAS"
    sudo rm -f -- "$CONFIG_ALIAS"
fi

# Remove only exact wallet exclusion lines from active configs. This works even
# when the dedicated Stratum config was already removed and ALGO can no longer
# be resolved on a retry.
shopt -s nullglob
for cfg in "$CONFIG_DIR"/*.conf; do
    [[ -f "$cfg" ]] || continue
    remove_exact_wallet_exclude "$cfg" "$WALLET_SYMBOL_UPPER"
    if [[ "$YIIMP_SYMBOL_UPPER" != "$WALLET_SYMBOL_UPPER" ]]; then
        remove_exact_wallet_exclude "$cfg" "$YIIMP_SYMBOL_UPPER"
    fi
done
shopt -u nullglob

for log_path in \
    /var/log/stratum-"${SYMBOL_LOWER}".log* \
    /var/log/stratum-"${SYMBOL_LOWER}"-boot.log*; do
    if compgen -G "$log_path" >/dev/null 2>&1; then
        :
    fi
done
sudo rm -f -- \
    /var/log/stratum-"${SYMBOL_LOWER}".log* \
    /var/log/stratum-"${SYMBOL_LOWER}"-boot.log* \
    2>/dev/null || true

# ------------------------------------------------------------
# Optional daemon purge
# ------------------------------------------------------------

if [[ "$PURGE_NODE" == true ]]; then
    if [[ "$NODE_TYPE" == "evm" ]]; then
        info "Stopping EVM node service: $DAEMON_SERVICE"
        sudo systemctl disable --now "$DAEMON_SERVICE" >/dev/null 2>&1 || true

        if [[ -e "$DAEMON_SERVICE_FILE" || -L "$DAEMON_SERVICE_FILE" ]]; then
            info "Removing EVM node service: $DAEMON_SERVICE_FILE"
            sudo rm -f -- "$DAEMON_SERVICE_FILE"
        fi
        sudo systemctl daemon-reload

        if [[ -n "$DAEMON_RUNNER" && ( -e "$DAEMON_RUNNER" || -L "$DAEMON_RUNNER" ) ]]; then
            info "Removing EVM node runner: $DAEMON_RUNNER"
            sudo rm -f -- "$DAEMON_RUNNER"
        fi

        if [[ -n "$RPC_HELPER_BINARY" && ( -e "/usr/bin/$RPC_HELPER_BINARY" || -L "/usr/bin/$RPC_HELPER_BINARY" ) ]]; then
            info "Removing EVM RPC helper: /usr/bin/$RPC_HELPER_BINARY"
            sudo rm -f -- "/usr/bin/$RPC_HELPER_BINARY"
        fi

        DAEMON_PATH="/usr/bin/$DAEMON_BINARY"
        if [[ ! -e "$DAEMON_PATH" && -e "/usr/local/bin/$DAEMON_BINARY" ]]; then
            DAEMON_PATH="/usr/local/bin/$DAEMON_BINARY"
        fi
        if [[ -e "$DAEMON_PATH" || -L "$DAEMON_PATH" ]]; then
            info "Removing EVM node binary: $DAEMON_PATH"
            remove_binary_and_aliases "$DAEMON_PATH"
        fi
    else
        DAEMON_PATH="/usr/bin/$DAEMON_BINARY"
        CLI_PATH="/usr/bin/$CLI_BINARY"

        if [[ ! -x "$DAEMON_PATH" && -x "/usr/local/bin/$DAEMON_BINARY" ]]; then
            DAEMON_PATH="/usr/local/bin/$DAEMON_BINARY"
        fi
        if [[ ! -x "$CLI_PATH" && -x "/usr/local/bin/$CLI_BINARY" ]]; then
            CLI_PATH="/usr/local/bin/$CLI_BINARY"
        fi

        remove_cron_lines "$STORAGE_USER" \
            "$DAEMON_PATH -datadir=$DAEMON_DATADIR" \
            "$DAEMON_BINARY -datadir=$DAEMON_DATADIR"

        if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" && "${SUDO_USER}" != "$STORAGE_USER" ]]; then
            remove_cron_lines "$SUDO_USER" \
                "$DAEMON_PATH -datadir=$DAEMON_DATADIR" \
                "$DAEMON_BINARY -datadir=$DAEMON_DATADIR"
        fi

        stop_daemon "$DAEMON_PATH" "$CLI_PATH" "$DAEMON_DATADIR" "$DAEMON_CONF"

        for binary_name in \
            "$DAEMON_BINARY" "$CLI_BINARY" "$TX_BINARY" "$UTIL_BINARY" \
            "$HASH_BINARY" "$WALLET_BINARY" "$QT_BINARY"; do
            [[ -n "$binary_name" ]] || continue
            if [[ -e "/usr/bin/$binary_name" || -L "/usr/bin/$binary_name" ]]; then
                remove_binary_and_aliases "/usr/bin/$binary_name"
            elif [[ -e "/usr/local/bin/$binary_name" || -L "/usr/local/bin/$binary_name" ]]; then
                remove_binary_and_aliases "/usr/local/bin/$binary_name"
            fi
        done

        if [[ -n "$DAEMON_BOOT_LOG" ]]; then
            sudo rm -f -- "$DAEMON_BOOT_LOG" "$DAEMON_BOOT_LOG".* 2>/dev/null || true
        fi
    fi

    if [[ "$KEEP_WALLET" == false && -e "$DAEMON_DATADIR" ]]; then
        case "$DAEMON_DATADIR" in
            "$STORAGE_ROOT"/wallets/.*)
                info "Removing daemon datadir/wallet: $DAEMON_DATADIR"
                sudo rm -rf -- "$DAEMON_DATADIR"
                ;;
            *)
                fatal "Refusing to recursively delete datadir outside $STORAGE_ROOT/wallets/.*: $DAEMON_DATADIR"
                ;;
        esac
    fi
fi

if [[ "$PURGE_BACKUPS" == true ]]; then
    remove_backups
fi

if [[ "$PURGE_DB" == true ]]; then
    purge_db_safely
fi

if [[ -e "$METADATA_FILE" ]]; then
    info "Removing managed metadata: $METADATA_FILE"
    sudo rm -f -- "$METADATA_FILE"
fi

# Remove managed directory only if empty.
if [[ -d "$MANAGED_DIR" ]]; then
    sudo rmdir "$MANAGED_DIR" 2>/dev/null || true
fi

hash -r 2>/dev/null || true

echo
log "===================================================="
log " Removal complete: $SYMBOL_UPPER"
log "===================================================="

if command -v "$WRAPPER" >/dev/null 2>&1 || [[ -e "$WRAPPER" ]]; then
    warn "Wrapper still exists: $WRAPPER"
else
    info "Stratum wrapper removed"
fi

if [[ -n "$CONFIG_PATH" && -e "$CONFIG_PATH" ]]; then
    warn "Config still exists: $CONFIG_PATH"
else
    info "Dedicated Stratum config removed"
fi

if [[ "$PURGE_NODE" == true ]]; then
    if [[ "$KEEP_WALLET" == true ]]; then
        info "Daemon datadir intentionally preserved: $DAEMON_DATADIR"
    elif [[ -e "$DAEMON_DATADIR" ]]; then
        warn "Daemon datadir still exists: $DAEMON_DATADIR"
    else
        info "Daemon datadir removed"
    fi
fi

info "Residual references (active Stratum paths only):"
{
    grep -RInF "$YIIMP_SYMBOL_UPPER" "$CONFIG_DIR" "$SERVICE_DIR" 2>/dev/null || true
    if [[ "$YIIMP_SYMBOL_UPPER" != "$SYMBOL_UPPER" ]]; then
        grep -RInF "$SYMBOL_LOWER" "$CONFIG_DIR" "$SERVICE_DIR" 2>/dev/null || true
    fi
} | grep -vE '(backup|\.bak|\.old|\.orig)' | head -50 || true
