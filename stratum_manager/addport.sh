#!/usr/bin/env bash

# === MEGAHASHPOOL FREE STRATUM PORT ===
#
# Safety rule:
#   - NEVER kill an unknown process just because it owns a TCP port.
#   - This helper only verifies that the selected port is free.
#
free_stratum_port() {
    local port="$1"
    local listeners=""
    local pids=""
    local pid=""
    local cmd=""

    if [[ -z "$port" ]]; then
        echo "ERROR: Stratum port is empty"
        return 1
    fi

    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo "ERROR: Invalid Stratum port: $port"
        return 1
    fi

    echo "INFO: Checking Stratum port $port..."

    listeners="$(
        sudo ss -lntpH 2>/dev/null |
        awk -v port="$port" '
            $4 ~ (":" port "$") {
                print
            }
        '
    )"

    if [[ -z "$listeners" ]]; then
        echo "SUCCESS: Port $port is available"
        return 0
    fi

    echo "ERROR: Port $port is already in use."
    echo "ERROR: SQSYIIMP will NOT terminate the owning process automatically."
    echo
    echo "Listener(s):"
    printf '%s\n' "$listeners"

    pids="$(
        printf '%s\n' "$listeners" |
        grep -oE 'pid=[0-9]+' |
        cut -d= -f2 |
        sort -u
    )"

    if [[ -n "$pids" ]]; then
        echo
        echo "Process(es):"

        for pid in $pids; do
            cmd="$(ps -p "$pid" -o args= 2>/dev/null || true)"
            printf '  PID %-8s %s\n' "$pid" "${cmd:-UNKNOWN}"
        done
    fi

    echo
    echo "Refusing to continue while port $port is occupied."
    return 1
}
# === END MEGAHASHPOOL FREE STRATUM PORT ===


############################################################
# Stratum Port Manager
# SabiasQue.Space
#
# Creates a dedicated coin Stratum configuration, lets the
# operator choose the runtime Stratum binary, and installs a
# per-coin launcher while preserving legacy addport behavior.
############################################################

source /etc/yiimpool.conf
source /etc/functions.sh
source /etc/daemonbuilder.sh
source "$STORAGE_ROOT/yiimp/.yiimp.conf"
if [ -f "$STORAGE_ROOT/daemon_builder/conf/info.sh" ]; then
    source "$STORAGE_ROOT/daemon_builder/conf/info.sh"
fi


############################################################
# SQSYIIMP ADDPORT UPDATE INTEGRATION
############################################################

SQSYIIMP_INSTALLED="$(
    sqsyiimp_get_installed_version 2>/dev/null || true
)"

SQSYIIMP_LATEST="$(
    sqsyiimp_get_latest_tag 2>/dev/null || true
)"

case "${1:-}" in
    -u|--update)
        echo
        echo "=== SQSYIIMP Update ==="
        echo

        if [[ -z "$SQSYIIMP_LATEST" ]]; then
            echo "ERROR: Unable to check the latest SQSYIIMP version."
            exit 1
        fi

        if ! sqsyiimp_version_is_newer \
            "$SQSYIIMP_INSTALLED" \
            "$SQSYIIMP_LATEST"
        then
            echo "SQSYIIMP is already up to date."
            echo "Installed : ${SQSYIIMP_INSTALLED:-unknown}"
            echo "Latest    : ${SQSYIIMP_LATEST}"
            exit 0
        fi

        echo "Installed : ${SQSYIIMP_INSTALLED:-unknown}"
        echo "Available : ${SQSYIIMP_LATEST}"
        echo

        sqsyiimp_run_updater
        exit $?
        ;;
esac

if sqsyiimp_version_is_newer \
    "$SQSYIIMP_INSTALLED" \
    "$SQSYIIMP_LATEST"
then
    echo
    echo "UPDATE: SQSYIIMP ${SQSYIIMP_LATEST} available (installed ${SQSYIIMP_INSTALLED})"
    echo "INFO: Run: addport --update"
    echo
fi

############################################################
# END SQSYIIMP ADDPORT UPDATE INTEGRATION
############################################################

STRATUM_DIR="${PATH_STRATUM:-$STORAGE_ROOT/yiimp/site/stratum}"


############################################################
# SQSYIIMP MANAGED STRATUM WRAPPERS
############################################################

# Managed Stratum controllers.
#
# Supported:
#
#   stratum.COIN start
#   stratum.COIN stop
#   stratum.COIN restart
#   stratum.COIN status
#
# A Stratum is HEALTHY only when:
#
#   1. its screen exists
#   2. the configured Stratum executable is really running
#   3. that executable owns the configured TCP listening port
#
# KAWPOW compatibility:
#
#   coin.kawpow.conf
#          ->
#   coin.kawpow
#
# Some stratum-kp builds strip ".conf" before opening the file.

sqsyiimp_ensure_runtime_alias() {
    local conf_path="$1"
    local config_dir=""
    local base=""
    local alias_path=""
    local target=""

    [[ -f "$conf_path" ]] || return 0

    config_dir="${conf_path%/*}"
    base="${conf_path##*/}"

    case "$base" in
        *.kawpow.conf)
            alias_path="$config_dir/${base%.conf}"
            ;;

        *)
            return 0
            ;;
    esac

    if [[ -L "$alias_path" ]]; then

        target="$(readlink "$alias_path" 2>/dev/null || true)"

        if [[ "$target" == "$base" ]]; then
            return 0
        fi

        sudo ln -sfn "$base" "$alias_path"
        return 0
    fi

    if [[ -e "$alias_path" ]]; then
        echo "WARNING: KAWPOW compatibility path already exists and is not a symlink:" >&2
        echo "         $alias_path" >&2
        return 0
    fi

    sudo ln -s "$base" "$alias_path"
}


sqsyiimp_refresh_stratum_wrappers() {
    local only_coin="${1:-}"
    local config_dir="${CONFIG_DIR:-${STRATUM_DIR}/config}"
    local control=""
    local base=""
    local coin=""
    local config=""
    local conf_path=""
    local runtime=""
    local tmp=""

    [[ -d "$config_dir" ]] || return 0

    shopt -s nullglob

    for control in "$config_dir"/stratum.*; do

        [[ -f "$control" ]] || continue

        base="${control##*/}"

        case "$base" in
            *.backup-*|*.bak|*.bak-*|*.old|*.orig|*.tmp)
                continue
                ;;
        esac

        coin="${base#stratum.}"

        [[ "$coin" =~ ^[A-Za-z0-9_-]+$ ]] || continue

        if [[ -n "$only_coin" && "$coin" != "$only_coin" ]]; then
            continue
        fi

        config=""

        # New managed wrapper.
        config="$(
            sed -nE \
                's/^[[:space:]]*CONFIG="([^"]+)"[[:space:]]*$/\1/p' \
                "$control" 2>/dev/null |
            head -n1
        )"

        # Legacy Addport wrapper.
        if [[ -z "$config" ]]; then
            config="$(
                sed -nE \
                    's|.*run\.sh[[:space:]]+([^"[:space:]]+).*|\1|p' \
                    "$control" 2>/dev/null |
                head -n1
            )"
        fi

        # Last resort: exactly one dedicated config.
        if [[ -z "$config" ]]; then

            mapfile -t candidates < <(
                find "$config_dir" \
                    -maxdepth 1 \
                    -type f \
                    -name "${coin}.*.conf" \
                    ! -name '*.backup-*' \
                    ! -name '*.bak*' \
                    -printf '%f\n' 2>/dev/null
            )

            if [[ "${#candidates[@]}" -eq 1 ]]; then
                config="${candidates[0]}"
            fi
        fi

        [[ "$config" =~ ^[A-Za-z0-9._-]+\.conf$ ]] || continue

        conf_path="$config_dir/$config"

        [[ -f "$conf_path" ]] || continue

        runtime="$(
            awk -F= '
                /^[[:space:]]*\[RUNTIME\][[:space:]]*$/ {
                    section=1
                    next
                }

                /^[[:space:]]*\[/ {
                    section=0
                }

                section && $1 ~ /^[[:space:]]*binary[[:space:]]*$/ {
                    value=$2
                    sub(/^[[:space:]]*/, "", value)
                    sub(/[[:space:]]*$/, "", value)
                    print value
                    exit
                }
            ' "$conf_path"
        )"

        # Never guess a binary.
        [[ -n "$runtime" ]] || continue
        [[ "$runtime" =~ ^[A-Za-z0-9._-]+$ ]] || continue

        #
        # stratum-kp KAWPOW compatibility.
        #
        sqsyiimp_ensure_runtime_alias "$conf_path"

        tmp="$(mktemp)"

        cat > "$tmp" <<'WRAPPER'
#!/usr/bin/env bash

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

STRATUM_DIR="$STORAGE_ROOT/yiimp/site/stratum"
CONFIG_DIR="$STRATUM_DIR/config"

SESSION="__SQSYIIMP_SESSION__"
CONFIG="__SQSYIIMP_CONFIG__"


stratum_as_runtime() {
    if [[ "$(id -un)" == "$STRATUM_USER" ]]; then
        "$@"
    else
        sudo -u "$STRATUM_USER" -H "$@"
    fi
}


stratum_ss_listeners() {
    local normal=""
    local privileged=""

    #
    # A process owner can normally see its own PID information.
    #
    normal="$(ss -lntpH 2>/dev/null || true)"

    #
    # When the caller has passwordless/cached sudo available,
    # prefer the privileged snapshot because it can also see
    # legacy Stratum processes owned by another user.
    #
    if command -v sudo >/dev/null 2>&1 &&
       sudo -n true >/dev/null 2>&1
    then
        privileged="$(sudo -n ss -lntpH 2>/dev/null || true)"
    fi

    if [[ -n "$privileged" ]]; then
        printf '%s\n' "$privileged"
    else
        printf '%s\n' "$normal"
    fi
}


stratum_runtime_binary() {
    awk -F= '
        /^[[:space:]]*\[RUNTIME\][[:space:]]*$/ {
            section=1
            next
        }

        /^[[:space:]]*\[/ {
            section=0
        }

        section && $1 ~ /^[[:space:]]*binary[[:space:]]*$/ {
            value=$2
            sub(/^[[:space:]]*/, "", value)
            sub(/[[:space:]]*$/, "", value)
            print value
            exit
        }
    ' "$CONFIG_DIR/$CONFIG"
}


stratum_tcp_port() {
    awk -F= '
        /^[[:space:]]*\[TCP\][[:space:]]*$/ {
            section=1
            next
        }

        /^[[:space:]]*\[/ {
            section=0
        }

        section && $1 ~ /^[[:space:]]*port[[:space:]]*$/ {
            value=$2
            sub(/^[[:space:]]*/, "", value)
            sub(/[[:space:]]*$/, "", value)
            print value
            exit
        }
    ' "$CONFIG_DIR/$CONFIG"
}


stratum_screen_running() {
    stratum_as_runtime screen -ls 2>/dev/null |
        grep -Eq "[[:space:]][0-9]+\.${SESSION}[[:space:]]"
}


stratum_real_process_pids() {
    local binary=""
    local expected_exe=""
    local config_path=""
    local config_alias=""
    local config_relative=""
    local config_relative_alias=""
    local runtime_uid=""
    local proc=""
    local pid=""
    local owner_uid=""
    local exe=""
    local exe_name=""
    local cmd=""
    local arg=""
    local config_matches=""

    binary="$(stratum_runtime_binary)"

    [[ -n "$binary" ]] || return 1

    expected_exe="$(
        readlink -f "$STRATUM_DIR/$binary" 2>/dev/null ||
        printf '%s\n' "$STRATUM_DIR/$binary"
    )"

    config_path="$CONFIG_DIR/$CONFIG"
    config_alias="$CONFIG_DIR/${CONFIG%.conf}"
    config_relative="config/$CONFIG"
    config_relative_alias="config/${CONFIG%.conf}"
    runtime_uid="$(id -u "$STRATUM_USER" 2>/dev/null || true)"

    [[ -n "$runtime_uid" ]] || return 1

    for proc in /proc/[0-9]*; do

        pid="${proc#/proc/}"
        owner_uid="$(stat -c '%u' "$proc" 2>/dev/null || true)"
        [[ "$owner_uid" == "$runtime_uid" ]] || continue

        exe="$(readlink "$proc/exe" 2>/dev/null || true)"

        if [[ -z "$exe" ]] &&
           command -v sudo >/dev/null 2>&1
        then
            exe="$(
                sudo -n readlink "$proc/exe" 2>/dev/null ||
                true
            )"
        fi

        exe="${exe% (deleted)}"

        cmd="$(
            tr '\0' ' ' 2>/dev/null < "$proc/cmdline" ||
            true
        )"

        if [[ -z "$cmd" ]]; then
            cmd="$(ps -p "$pid" -o args= 2>/dev/null || true)"
        fi

        [[ -n "$cmd" ]] || continue

        config_matches="n"
        while IFS= read -r -d '' arg; do
            if [[ "$arg" == "$config_path" ||
                  "$arg" == "$config_alias" ||
                  "$arg" == "$config_relative" ||
                  "$arg" == "$config_relative_alias" ||
                  "$arg" == "$CONFIG" ||
                  "$arg" == "${CONFIG%.conf}" ]]
            then
                config_matches="y"
                break
            fi
        done < "$proc/cmdline" 2>/dev/null || true

        [[ "$config_matches" == "y" ]] || continue

        if [[ -n "$exe" ]]; then
            exe_name="${exe##*/}"
            if [[ "$exe" != "$expected_exe" && "$exe_name" != stratum* ]]; then
                continue
            fi
        else
            #
            # Cross-user /proc restrictions can hide exe.
            # In that case require both the expected binary path
            # and the expected configuration in the command line.
            #
            [[ "$cmd" == *"stratum"* ]] || continue
        fi

        printf '%s\n' "$pid"
    done
}


stratum_terminate_managed_processes() {
    local signal="${1:-TERM}"
    local pid=""
    local found="n"

    while read -r pid; do
        [[ -n "$pid" ]] || continue
        found="y"
        stratum_as_runtime kill "-$signal" "$pid" 2>/dev/null || true
    done < <(stratum_real_process_pids)

    [[ "$found" == "y" ]]
}


stratum_real_process_running() {
    [[ -n "$(stratum_real_process_pids)" ]]
}


stratum_real_process_lines() {
    local pid=""

    while read -r pid; do

        [[ -n "$pid" ]] || continue

        ps -p "$pid" -o pid=,args= 2>/dev/null || true

    done < <(stratum_real_process_pids)
}


stratum_port_listening() {
    local port=""
    local pid=""

    port="$(stratum_tcp_port)"

    [[ -n "$port" ]] || return 1

    while read -r pid; do

        [[ -n "$pid" ]] || continue

        if stratum_ss_listeners |
           awk \
             -v port="$port" \
             -v needle="pid=$pid," '
                $4 ~ (":" port "$") &&
                index($0, needle) {
                    found=1
                }

                END {
                    exit(found ? 0 : 1)
                }
             '
        then
            return 0
        fi

    done < <(stratum_real_process_pids)

    return 1
}


stratum_healthy() {
    stratum_screen_running &&
    stratum_real_process_running &&
    stratum_port_listening
}


stratum_start() {
    local binary=""
    local port=""
    local i=""

    if [[ ! -f "$CONFIG_DIR/$CONFIG" ]]; then
        echo "ERROR: Stratum configuration not found:"
        echo "       $CONFIG_DIR/$CONFIG"
        return 1
    fi

    binary="$(stratum_runtime_binary)"
    port="$(stratum_tcp_port)"

    if [[ -z "$binary" ]]; then
        echo "ERROR: [RUNTIME] binary is not configured in:"
        echo "       $CONFIG_DIR/$CONFIG"
        return 1
    fi

    if [[ ! -x "$STRATUM_DIR/$binary" ]]; then
        echo "ERROR: configured Stratum binary is not executable:"
        echo "       $STRATUM_DIR/$binary"
        return 1
    fi

    if [[ -z "$port" ]]; then
        echo "ERROR: TCP port is not configured."
        return 1
    fi

    if stratum_healthy; then
        echo "${SESSION^^} is already running and healthy."
        return 0
    fi

    #
    # A screen without a real Stratum + listening port
    # is not considered a valid running service.
    #
    if stratum_screen_running; then

        echo "WARNING: stale/unhealthy ${SESSION^^} screen detected."
        echo "Removing stale screen..."

        stratum_as_runtime screen -S "$SESSION" -X quit 2>/dev/null || true

        for i in $(seq 1 10); do

            if ! stratum_screen_running &&
               ! stratum_real_process_running
            then
                break
            fi

            sleep 1
        done
    fi

    if stratum_real_process_running; then
        echo "ERROR: real Stratum process remains without a healthy screen."
        stratum_real_process_lines
        return 1
    fi

    echo "Starting ${SESSION^^}..."

    stratum_as_runtime screen -dmS "$SESSION" \
        bash "$STRATUM_DIR/run.sh" "$CONFIG"

    #
    # Wait up to 30 seconds.
    #
    # Success requires:
    #
    #   screen + real executable + owned listening port
    #
    for i in $(seq 1 30); do

        if stratum_healthy; then

            echo "${SESSION^^} started successfully."
            echo "Process:"
            stratum_real_process_lines
            echo "Port   : $port LISTENING"

            return 0
        fi

        if ! stratum_screen_running; then
            echo "ERROR: ${SESSION^^} screen terminated during startup."
            return 1
        fi

        sleep 1
    done

    echo "ERROR: ${SESSION^^} startup health check timed out."
    echo

    stratum_status

    return 1
}


stratum_stop() {
    local i=""

    if ! stratum_screen_running; then

        if stratum_real_process_running; then

            echo "WARNING: ${SESSION^^} has a real Stratum process without screen:"
            stratum_real_process_lines
            echo "Stopping the managed orphan process..."
            stratum_terminate_managed_processes TERM || true

            for i in $(seq 1 10); do
                if ! stratum_real_process_running; then
                    echo "${SESSION^^} orphan process stopped successfully."
                    return 0
                fi
                sleep 1
            done

            echo "WARNING: managed process ignored TERM; sending KILL."
            stratum_terminate_managed_processes KILL || true
            sleep 1

            if ! stratum_real_process_running; then
                echo "${SESSION^^} orphan process stopped successfully."
                return 0
            fi

            echo "ERROR: managed orphan process could not be stopped."
            return 1
        fi

        echo "${SESSION^^} is not running."
        return 0
    fi

    echo "Stopping ${SESSION^^}..."

    stratum_as_runtime screen -S "$SESSION" -X quit 2>/dev/null || true

    for i in $(seq 1 10); do

        if ! stratum_screen_running &&
           ! stratum_real_process_running
        then
            echo "${SESSION^^} stopped successfully."
            return 0
        fi

        sleep 1
    done

    if stratum_real_process_running; then
        echo "WARNING: managed process remained after screen stopped; sending TERM."
        stratum_terminate_managed_processes TERM || true

        for i in $(seq 1 10); do
            if ! stratum_real_process_running; then
                echo "${SESSION^^} stopped successfully."
                return 0
            fi
            sleep 1
        done

        echo "WARNING: managed process ignored TERM; sending KILL."
        stratum_terminate_managed_processes KILL || true
        sleep 1
    fi

    echo "ERROR: ${SESSION^^} did not stop cleanly."

    if stratum_real_process_running; then
        echo "Remaining process:"
        stratum_real_process_lines
    fi

    return 1
}


stratum_restart() {
    stratum_stop || return 1
    sleep 1
    stratum_start
}


stratum_mining_snapshot() {
    local tmp=""
    local line=""
    local coinds=""
    local jobs=""
    local clients=""
    local state="UNKNOWN"

    if ! stratum_screen_running; then
        echo "UNKNOWN|||"
        return 0
    fi

    tmp="$(stratum_as_runtime mktemp 2>/dev/null || true)"

    if [[ -z "$tmp" ]]; then
        echo "UNKNOWN|||"
        return 0
    fi

    if ! stratum_as_runtime screen -S "$SESSION" \
        -X hardcopy -h "$tmp" \
        >/dev/null 2>&1
    then
        stratum_as_runtime rm -f "$tmp" >/dev/null 2>&1 || true
        echo "UNKNOWN|||"
        return 0
    fi

    line="$(
        stratum_as_runtime grep -E \
          'STATS[[:space:]]+coinds=[0-9]+[[:space:]]+jobs=[0-9]+[[:space:]]+clients=[0-9]+' \
          "$tmp" 2>/dev/null |
        tail -n1
    )"

    stratum_as_runtime rm -f "$tmp" >/dev/null 2>&1 || true

    if [[ -z "$line" ]]; then
        echo "UNKNOWN|||"
        return 0
    fi

    coinds="$(
        sed -nE \
          's/.*coinds=([0-9]+).*/\1/p' \
          <<<"$line"
    )"

    jobs="$(
        sed -nE \
          's/.*jobs=([0-9]+).*/\1/p' \
          <<<"$line"
    )"

    clients="$(
        sed -nE \
          's/.*clients=([0-9]+).*/\1/p' \
          <<<"$line"
    )"

    coinds="${coinds:-0}"
    jobs="${jobs:-0}"
    clients="${clients:-0}"

    if (( coinds > 0 && jobs > 0 && clients > 0 )); then
        state="ACTIVE"
    elif (( coinds > 0 && jobs > 0 )); then
        state="READY_NO_MINERS"
    else
        state="INACTIVE"
    fi

    echo "${state}|${coinds}|${jobs}|${clients}"
}


stratum_status() {
    local binary=""
    local port=""
    local pid=""
    local screen_ok=0
    local process_ok=0
    local port_ok=0
    local service_state="STOPPED"

    local mining_data=""
    local mining_state=""
    local mining_coinds=""
    local mining_jobs=""
    local mining_clients=""

    local -a pids=()

    binary="$(stratum_runtime_binary)"
    port="$(stratum_tcp_port)"

    #
    # One process snapshot for the complete status calculation.
    #
    mapfile -t pids < <(stratum_real_process_pids)

    echo "===== ${SESSION^^} STATUS ====="

    if stratum_screen_running; then

        screen_ok=1

        echo "Screen  : RUNNING"

        stratum_as_runtime screen -ls |
            grep -E "[[:space:]][0-9]+\.${SESSION}[[:space:]]" ||
            true

    else
        echo "Screen  : STOPPED"
    fi

    if (( ${#pids[@]} > 0 )); then

        process_ok=1

        echo "Process : RUNNING"

        for pid in "${pids[@]}"; do
            ps -p "$pid" -o pid=,args= 2>/dev/null || true
        done

    else
        echo "Process : STOPPED"
    fi

    echo "Config  : $CONFIG"
    echo "Binary  : ${binary:-NOT CONFIGURED}"

    #
    # Port must belong to one of the PID values captured above.
    #
    if [[ -n "$port" ]] && (( process_ok )); then

        for pid in "${pids[@]}"; do

            if stratum_ss_listeners |
               awk \
                 -v port="$port" \
                 -v needle="pid=$pid," '
                    $4 ~ (":" port "$") &&
                    index($0, needle) {
                        found=1
                    }

                    END {
                        exit(found ? 0 : 1)
                    }
                 '
            then
                port_ok=1
                break
            fi

        done
    fi

    if [[ -z "$port" ]]; then

        echo "Port    : NOT CONFIGURED"

    elif (( port_ok )); then

        echo "Port    : $port LISTENING"

    else
        echo "Port    : $port NOT LISTENING"
    fi

    #
    # SERVICE state:
    # only local Stratum process/screen/port.
    #
    if (( screen_ok && process_ok && port_ok )); then
        service_state="HEALTHY"

    elif (( screen_ok || process_ok )); then
        service_state="DEGRADED"

    else
        service_state="STOPPED"
    fi

    echo "Service : $service_state"

    #
    # MINING state:
    # based on latest Stratum STATS line.
    #
    mining_data="$(stratum_mining_snapshot)"

    IFS='|' read -r \
        mining_state \
        mining_coinds \
        mining_jobs \
        mining_clients \
        <<<"$mining_data"

    echo "Mining  : ${mining_state:-UNKNOWN}"

    if [[ -n "$mining_coinds" ]]; then
        echo "Coinds  : $mining_coinds"
    fi

    if [[ -n "$mining_jobs" ]]; then
        echo "Jobs    : $mining_jobs"
    fi

    if [[ -n "$mining_clients" ]]; then
        echo "Clients : $mining_clients"
    fi

    if [[ "$service_state" == "HEALTHY" ]] &&
       [[ "$mining_state" == "INACTIVE" ]]
    then
        echo "Warning : Stratum is running but mining is not ready"
    fi
}

case "${1:-}" in

    start)
        stratum_start
        ;;

    stop)
        stratum_stop
        ;;

    restart)
        stratum_restart
        ;;

    status)
        stratum_status
        ;;

    *)
        echo "Usage: $(basename "$0") {start|stop|restart|status}"
        exit 1
        ;;

esac
WRAPPER

        sed -i \
            -e "s/__SQSYIIMP_SESSION__/${coin}/g" \
            -e "s/__SQSYIIMP_CONFIG__/${config}/g" \
            "$tmp"

        if ! bash -n "$tmp"; then

            echo "WARNING: generated wrapper failed syntax check: $coin" >&2

            rm -f "$tmp"
            continue
        fi

        if ! cmp -s "$tmp" "$control"; then

            sudo install \
                -o root \
                -g root \
                -m 755 \
                "$tmp" \
                "$control"
        fi

        if [[ ! -f "/usr/bin/stratum.$coin" ]] ||
           ! cmp -s "$tmp" "/usr/bin/stratum.$coin"
        then

            sudo install \
                -o root \
                -g root \
                -m 755 \
                "$tmp" \
                "/usr/bin/stratum.$coin"
        fi

        rm -f "$tmp"

    done

    shopt -u nullglob

    return 0
}


############################################################
# END SQSYIIMP MANAGED STRATUM WRAPPERS
############################################################

CONFIG_DIR="$STRATUM_DIR/config"
SERVICE_DIR="$STRATUM_DIR/services"
RUNNER="$STRATUM_DIR/runner.sh"
DEFAULT_STRATUM_BINARY="stratum"

print_manager_header() {
    print_header "Stratum Port Manager"
    print_info "Stratum directory : $STRATUM_DIR"
    print_info "Config directory  : $CONFIG_DIR"
}

fatal() {
    print_error "$1"
    exit 1
}

ensure_layout() {
    [ -d "$STRATUM_DIR" ] || fatal "Stratum directory not found: $STRATUM_DIR"
    [ -d "$CONFIG_DIR" ] || fatal "Stratum config directory not found: $CONFIG_DIR"
    sudo mkdir -p "$SERVICE_DIR"
}

find_open_port() {
    local lower=2768
    local upper=6999
    local candidate

    while true; do
        candidate=$((lower + (RANDOM % (upper - lower + 1))))
        if ! ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$candidate$"; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
}


ensure_sha256d_template() {
    local source="$CONFIG_DIR/sha.conf"
    local target="$CONFIG_DIR/sha256d.conf"
    local runtime_user="${STORAGE_USER:-crypto-data}"
    local runtime_group="${STORAGE_GROUP:-${STORAGE_USER:-crypto-data}}"

    #
    # sha and sha256d are intentionally separate algorithms.
    #
    # Do not overwrite an administrator-provided sha256d
    # template. Only bootstrap it when sha.conf exists and
    # sha256d.conf is missing.
    #
    if [[ -f "$target" ]]; then
        return 0
    fi

    if [[ ! -f "$source" ]]; then
        return 0
    fi

    print_info \
        "Creating independent SHA256d Stratum template: $target"

    sudo cp -a \
        "$source" \
        "$target" ||
        fatal "Unable to create SHA256d template"

    sudo sed -i -E \
        's/^[[:space:]]*algo[[:space:]]*=.*/algo = sha256d/' \
        "$target" ||
        fatal "Unable to configure SHA256d algorithm"

    if ! sudo grep -qEi \
        '^[[:space:]]*algo[[:space:]]*=[[:space:]]*sha256d[[:space:]]*$' \
        "$target"
    then
        sudo rm -f "$target"
        fatal "SHA256d template validation failed"
    fi

    sudo chown \
        "$runtime_user:$runtime_group" \
        "$target"

    print_success \
        "SHA256d algorithm template available"
}


list_algorithms() {
    find "$CONFIG_DIR" \
        -mindepth 1 -maxdepth 1 -type f \
        -not -name '.*' \
        -not -name '*.sh' \
        -not -name '*.log' \
        -not -name 'stratum.*' \
        -not -name '*.*.*' \
        -iname '*.conf' \
        -printf '%f\n' \
    | sed 's/\.conf$//' \
    | sort -u
}

select_algorithm() {
    local requested="${1:-}"
    local -a algorithms=()
    local selected=""
    local tmpfile
    local i

    mapfile -t algorithms < <(list_algorithms)
    [ "${#algorithms[@]}" -gt 0 ] || fatal "No base algorithm configs were found in $CONFIG_DIR"

    if [ -n "$requested" ]; then
        for i in "${algorithms[@]}"; do
            if [ "$i" = "$requested" ]; then
                SELECTED_ALGO="$requested"
                return 0
            fi
        done
        fatal "Algorithm config not found: $requested.conf"
    fi

    if command -v dialog >/dev/null 2>&1 && [ -t 0 ] && [ -t 1 ]; then
        local -a dialog_items=()
        for i in "${algorithms[@]}"; do
            dialog_items+=("$i" "available")
        done

        tmpfile=$(mktemp)
        if dialog \
            --clear \
            --title "SQSYIIMP | Select Algorithm" \
            --no-cancel \
            --menu "Select the mining algorithm for ${coinsymbol^^}." \
            24 72 16 \
            "${dialog_items[@]}" \
            2>"$tmpfile"; then
            selected=$(<"$tmpfile")
        fi
        rm -f "$tmpfile"
        [ -t 1 ] && clear
    else
        echo
        print_info "Available algorithms:"
        select selected in "${algorithms[@]}"; do
            [ -n "$selected" ] && break
            print_warning "Invalid selection"
        done
    fi

    [ -n "$selected" ] || fatal "No algorithm selected"
    SELECTED_ALGO="$selected"
}

is_stratum_backup_name() {
    local name="$1"

    case "$name" in
        *.bak|*.bak.*|*.bak-*|*.backup|*.backup.*|*.backup-*|*.old|*.old.*|*.old-*|*.orig|*.orig.*|*.save|*.save.*|*.disabled|*~)
            return 0
            ;;
    esac

    return 1
}

list_stratum_binaries() {
    local file
    local name

    for file in "$STRATUM_DIR"/stratum*; do
        [ -f "$file" ] || continue
        [ -x "$file" ] || continue

        name=${file##*/}

        case "$name" in
            runner.sh|run.sh|blocknotify|blocknotify.sh|*.sh|*.conf|*.log)
                continue
                ;;
        esac

        is_stratum_backup_name "$name" && continue

        case "$name" in
            stratum|stratum-*|stratum_*|stratum.*)
                printf '%s\n' "$name"
                ;;
        esac
    done
}

stratum_binary_exists() {
    local name="$1"

    [ -n "$name" ] || return 1
    [ "$name" = "${name##*/}" ] || return 1
    [ -x "$STRATUM_DIR/$name" ] || return 1

    is_stratum_backup_name "$name" && return 1

    case "$name" in
        stratum|stratum-*|stratum_*|stratum.*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

get_pool_coinbase_tag() {
    local server_config="/etc/yiimp/serverconfig.php"
    local tag=""

    if [ -f "$server_config" ] && command -v php >/dev/null 2>&1; then
        tag=$(php -r '
            require "/etc/yiimp/serverconfig.php";
            if (defined("YAAMP_SITE_NAME")) {
                echo YAAMP_SITE_NAME;
            } elseif (defined("YIIMP_SITE_NAME")) {
                echo YIIMP_SITE_NAME;
            }
        ' 2>/dev/null || true)
    fi

    if [ -z "$tag" ]; then
        return 1
    fi

    if [ "${#tag}" -ge 32 ]; then
        print_warning "Pool name is too long for coinbaseextra; inherited config value will be kept"
        return 1
    fi

    if ! LC_ALL=C printf '%s' "$tag" | grep -qE '^[ -~]+$'; then
        print_warning "Pool name contains non-printable ASCII characters; inherited config value will be kept"
        return 1
    fi

    printf '%s\n' "$tag"
}

binary_description() {
    local name="$1"
    local path="$STRATUM_DIR/$name"
    local bytes
    local human

    bytes=$(stat -c '%s' "$path" 2>/dev/null || echo 0)
    if command -v numfmt >/dev/null 2>&1; then
        human=$(numfmt --to=iec-i --suffix=B "$bytes" 2>/dev/null || echo "${bytes}B")
    else
        human="${bytes}B"
    fi
    printf '%s' "$human"
}

select_stratum_binary() {
    local requested="${1:-${STRATUM_BINARY:-${SQS_STRATUM_BINARY:-}}}"
    local -a binaries=()
    local -a dialog_items=()
    local selected=""
    local tmpfile
    local item

    mapfile -t binaries < <(list_stratum_binaries | sort -u)
    [ "${#binaries[@]}" -gt 0 ] || fatal "No executable Stratum binaries were found in $STRATUM_DIR"

    if [ -n "$requested" ]; then
        if stratum_binary_exists "$requested"; then
            SELECTED_STRATUM_BINARY="$requested"
            return 0
        fi
        fatal "Requested Stratum binary is not available: $requested"
    fi

    if [ "${#binaries[@]}" -eq 1 ]; then
        SELECTED_STRATUM_BINARY="${binaries[0]}"
        print_info "Only one Stratum binary is available; selected ${binaries[0]}"
        return 0
    fi

    if [ ! -t 0 ] || [ ! -t 1 ]; then
        if stratum_binary_exists "$DEFAULT_STRATUM_BINARY"; then
            SELECTED_STRATUM_BINARY="$DEFAULT_STRATUM_BINARY"
            print_warning "Non-interactive session detected; selected default binary: $DEFAULT_STRATUM_BINARY"
            return 0
        fi
        fatal "Multiple Stratum binaries are available and no binary was specified"
    fi

    echo
    print_info "Available Stratum binaries in $STRATUM_DIR:"
    for item in "${binaries[@]}"; do
        printf '  - %-32s %s\n' "$item" "$(binary_description "$item")"
    done
    echo

    if command -v dialog >/dev/null 2>&1; then
        for item in "${binaries[@]}"; do
            dialog_items+=("$item" "$(binary_description "$item")")
        done

        tmpfile=$(mktemp)
        if dialog \
            --clear \
            --title "Select Stratum Binary" \
            --no-cancel \
            --menu "Choose the Stratum executable for ${coinsymbol^^} (${SELECTED_ALGO})." \
            24 82 16 \
            "${dialog_items[@]}" \
            2>"$tmpfile"; then
            selected=$(<"$tmpfile")
        fi
        rm -f "$tmpfile"
        [ -t 1 ] && clear
    else
        select selected in "${binaries[@]}"; do
            [ -n "$selected" ] && break
            print_warning "Invalid selection"
        done
    fi

    [ -n "$selected" ] || fatal "No Stratum binary selected"
    stratum_binary_exists "$selected" || fatal "Selected Stratum binary is not executable: $selected"
    SELECTED_STRATUM_BINARY="$selected"
}

upsert_simple_key() {
    local file="$1"
    local section="$2"
    local key="$3"
    local value="$4"
    local tmpfile

    tmpfile=$(mktemp)
    awk -v target_section="$section" -v target_key="$key" -v target_value="$value" '
        function section_name(line, value) {
            value = line
            sub(/^[[:space:]]*\[/, "", value)
            sub(/\][[:space:]]*$/, "", value)
            return value
        }
        BEGIN {
            in_target = 0
            section_seen = 0
            key_written = 0
        }
        /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
            if (in_target && !key_written) {
                print target_key " = " target_value
                key_written = 1
            }
            current = section_name($0)
            in_target = (tolower(current) == tolower(target_section))
            if (in_target) section_seen = 1
            print
            next
        }
        {
            if (in_target && $0 ~ "^[[:space:]]*" target_key "[[:space:]]*=") {
                if (!key_written) {
                    print target_key " = " target_value
                    key_written = 1
                }
                next
            }
            print
        }
        END {
            if (in_target && !key_written) {
                print target_key " = " target_value
                key_written = 1
            }
            if (!section_seen) {
                print ""
                print "[" target_section "]"
                print target_key " = " target_value
            }
        }
    ' "$file" >"$tmpfile" || {
        rm -f "$tmpfile"
        fatal "Unable to update $key in $file"
    }

    sudo cp "$tmpfile" "$file"
    rm -f "$tmpfile"
}

remove_simple_key() {
    local file="$1"
    local section="$2"
    local key="$3"
    local tmpfile

    tmpfile=$(mktemp)
    awk -v target_section="$section" -v target_key="$key" '
        function section_name(line, value) {
            value = line
            sub(/^[[:space:]]*\[/, "", value)
            sub(/\][[:space:]]*$/, "", value)
            return value
        }
        /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
            current = section_name($0)
            in_target = (tolower(current) == tolower(target_section))
            print
            next
        }
        {
            if (in_target && $0 ~ "^[[:space:]]*" target_key "[[:space:]]*=") next
            print
        }
    ' "$file" >"$tmpfile" || {
        rm -f "$tmpfile"
        fatal "Unable to remove $key from $file"
    }

    sudo cp "$tmpfile" "$file"
    rm -f "$tmpfile"
}

get_simple_key() {
    local file="$1"
    local section="$2"
    local key="$3"

    [[ -f "$file" ]] || return 1

    awk -v target_section="$section" -v target_key="$key" '
        function section_name(line, value) {
            value = line
            sub(/^[[:space:]]*\[/, "", value)
            sub(/\][[:space:]]*$/, "", value)
            return value
        }
        /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
            current = section_name($0)
            in_target = (tolower(current) == tolower(target_section))
            next
        }
        in_target && $0 ~ "^[[:space:]]*" target_key "[[:space:]]*=" {
            value = $0
            sub(/^[^=]*=[[:space:]]*/, "", value)
            sub(/[[:space:]]*[;#].*$/, "", value)
            sub(/[[:space:]]*$/, "", value)
            print value
            exit
        }
    ' "$file"
}

is_positive_number() {
    local value="$1"

    [[ "$value" =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]] || return 1
    awk -v value="$value" 'BEGIN { exit !(value > 0) }'
}

number_le() {
    local left="$1"
    local right="$2"

    awk -v left="$left" -v right="$right" 'BEGIN { exit !(left <= right) }'
}

read_number_with_default() {
    local prompt="$1"
    local default_value="$2"
    local value=""

    while true; do
        read -r -e -p "$prompt [$default_value]: " value
        value="${value:-$default_value}"

        if is_positive_number "$value"; then
            printf '%s\n' "$value"
            return 0
        fi

        print_warning "Enter a positive number, for example: $default_value" >&2
    done
}

number_multiply() {
    local value="$1"
    local multiplier="$2"

    awk -v value="$value" -v multiplier="$multiplier" \
        'BEGIN { printf "%.15g\n", value * multiplier }'
}

nicehash_algorithm_name() {
    case "${SELECTED_ALGO,,}" in
        scrypt) printf '%s\n' "Scrypt" ;;
        sha|sha256|sha256d) printf '%s\n' "SHA256" ;;
        x11) printf '%s\n' "X11" ;;
        neoscrypt) printf '%s\n' "NeoScrypt" ;;
        ethash|daggerhashimoto) printf '%s\n' "DaggerHashimoto" ;;
        equihash) printf '%s\n' "Equihash" ;;
        zhash|equihash144_5) printf '%s\n' "ZHash" ;;
        randomx|randomxmonero) printf '%s\n' "RandomXmonero" ;;
        eaglesong) printf '%s\n' "Eaglesong" ;;
        kawpow) printf '%s\n' "KAWPOW" ;;
        beamv3|beamhashiii) printf '%s\n' "BeamV3" ;;
        octopus) printf '%s\n' "Octopus" ;;
        autolykos|autolykos2) printf '%s\n' "Autolykos" ;;
        etchash) printf '%s\n' "ETCHash" ;;
        verushash|verus) printf '%s\n' "VerusHash" ;;
        kheavyhash) printf '%s\n' "KHeavyHash" ;;
        nexapow|nexa) printf '%s\n' "NexaPow" ;;
        alephium|blake3) printf '%s\n' "Alephium" ;;
        fishhash) printf '%s\n' "FishHash" ;;
        *) return 1 ;;
    esac
}

nicehash_fallback_minimum() {
    case "$1" in
        Scrypt) printf '%s\n' "50000" ;;
        SHA256) printf '%s\n' "500000" ;;
        X11) printf '%s\n' "256" ;;
        NeoScrypt) printf '%s\n' "16383" ;;
        DaggerHashimoto|ETCHash) printf '%s\n' "2" ;;
        Equihash) printf '%s\n' "131072" ;;
        ZHash) printf '%s\n' "1024" ;;
        RandomXmonero) printf '%s\n' "262144" ;;
        Eaglesong) printf '%s\n' "128000000000" ;;
        KAWPOW) printf '%s\n' "1024000000" ;;
        BeamV3) printf '%s\n' "2048" ;;
        Octopus) printf '%s\n' "10000000000" ;;
        Autolykos) printf '%s\n' "4000000000" ;;
        VerusHash) printf '%s\n' "1000000" ;;
        KHeavyHash) printf '%s\n' "16384" ;;
        NexaPow) printf '%s\n' "0.1" ;;
        Alephium) printf '%s\n' "549755813888" ;;
        FishHash) printf '%s\n' "100000000" ;;
        *) return 1 ;;
    esac
}

get_nicehash_minimum() {
    local algorithm_name=""
    local api_value=""

    algorithm_name="$(nicehash_algorithm_name || true)"
    [[ -n "$algorithm_name" ]] || return 1

    if command -v curl >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
        api_value="$(
            curl -fsS --connect-timeout 3 --max-time 8 \
                'https://api2.nicehash.com/main/api/v2/public/buy/info' 2>/dev/null |
                python3 -c '
import json, sys
target = sys.argv[1].lower()
try:
    data = json.load(sys.stdin)
    for item in data.get("miningAlgorithms", []):
        if str(item.get("name", "")).lower() == target:
            value = item.get("min_diff_initial")
            if value is not None:
                print(value)
            break
except (ValueError, TypeError):
    pass
' "$algorithm_name" 2>/dev/null || true
        )"
    fi

    if is_positive_number "$api_value"; then
        printf '%s\n' "$api_value"
        return 0
    fi

    api_value="$(nicehash_fallback_minimum "$algorithm_name" || true)"
    if is_positive_number "$api_value"; then
        printf '%s\n' "$api_value"
        return 0
    fi

    return 1
}

get_template_difficulty() {
    local base_config="$CONFIG_DIR/$SELECTED_ALGO.conf"
    local value=""

    value="$(get_simple_key "$base_config" "STRATUM" "difficulty" || true)"
    is_positive_number "$value" || return 1
    printf '%s\n' "$value"
}

configure_marketplace_profiles() {
    local coin_config="$CONFIG_DIR/$coinsymbollower.$SELECTED_ALGO.conf"
    local answer=""
    local existing_initial=""
    local existing_min=""
    local existing_max=""
    local recommended_nicehash=""
    local recommended_mrr=""
    local nicehash_supported="y"
    local nicehash_prompt="Enable NiceHash compatibility? (Y/n): "

    nicehash_enabled="y"
    recommended_nicehash="$(get_nicehash_minimum || true)"
    if ! is_positive_number "$recommended_nicehash"; then
        nicehash_supported="n"
        nicehash_enabled="n"
        recommended_nicehash="$(get_template_difficulty || true)"
        recommended_nicehash="${recommended_nicehash:-1}"
        nicehash_prompt="NiceHash does not list this algorithm. Enable manually? (y/N): "
    fi
    nicehash_initial="$recommended_nicehash"
    nicehash_diff_min="$recommended_nicehash"
    nicehash_diff_max="$(number_multiply "$recommended_nicehash" 1024)"
    mrr_enabled="y"
    recommended_mrr="$(get_template_difficulty || true)"
    recommended_mrr="${recommended_mrr:-1}"
    mrr_initial="$recommended_mrr"
    mrr_diff_min="$recommended_mrr"
    mrr_diff_max="$(number_multiply "$recommended_mrr" 1024)"

    if [[ -f "$coin_config" ]]; then
        existing_initial="$(get_simple_key "$coin_config" "STRATUM" "nicehash" || true)"
        existing_min="$(get_simple_key "$coin_config" "STRATUM" "nicehash_diff_min" || true)"
        existing_max="$(get_simple_key "$coin_config" "STRATUM" "nicehash_diff_max" || true)"

        if is_positive_number "$existing_initial" &&
            is_positive_number "$existing_min" &&
            is_positive_number "$existing_max" &&
            number_le "$existing_min" "$existing_initial" &&
            number_le "$existing_initial" "$existing_max"
        then
            nicehash_enabled="y"
            nicehash_initial="$existing_initial"
            nicehash_diff_min="$existing_min"
            nicehash_diff_max="$existing_max"
        fi

        existing_initial="$(get_simple_key "$coin_config" "STRATUM" "mrr" || true)"
        existing_min="$(get_simple_key "$coin_config" "STRATUM" "mrr_diff_min" || true)"
        existing_max="$(get_simple_key "$coin_config" "STRATUM" "mrr_diff_max" || true)"

        if is_positive_number "$existing_initial" &&
            is_positive_number "$existing_min" &&
            is_positive_number "$existing_max" &&
            number_le "$existing_min" "$existing_initial" &&
            number_le "$existing_initial" "$existing_max"
        then
            mrr_initial="$existing_initial"
            mrr_diff_min="$existing_min"
            mrr_diff_max="$existing_max"
        fi
    fi

    echo
    print_info "Difficulty recommendations for algorithm: $SELECTED_ALGO"
    if [[ "$nicehash_supported" == "y" ]]; then
        print_info "NiceHash official minimum : $recommended_nicehash"
        print_info "NiceHash suggested profile: initial=$recommended_nicehash, min=$recommended_nicehash, max=$(number_multiply "$recommended_nicehash" 1024)"
        print_info "NiceHash source           : live API, with local fallback table"
    else
        print_warning "NiceHash does not currently list $SELECTED_ALGO; compatibility is disabled by default"
    fi
    print_info "MRR suggested minimum     : $recommended_mrr (algorithm template difficulty)"
    print_info "MRR suggested profile     : initial=$recommended_mrr, min=$recommended_mrr, max=$(number_multiply "$recommended_mrr" 1024)"
    print_info "MRR has no universal minimum; adjust the profile to the rented rig's hashrate/difficulty"

    if [[ "$nicehash_initial" != "$recommended_nicehash" ||
          "$nicehash_diff_min" != "$recommended_nicehash" ]]
    then
        print_info "Existing NiceHash profile : initial=$nicehash_initial, min=$nicehash_diff_min, max=$nicehash_diff_max"
    fi

    if [[ "$mrr_initial" != "$recommended_mrr" ||
          "$mrr_diff_min" != "$recommended_mrr" ]]
    then
        print_info "Existing MRR profile      : initial=$mrr_initial, min=$mrr_diff_min, max=$mrr_diff_max"
    fi

    if [[ ! -t 0 ]]; then
        print_info "Non-interactive mode: using current/recommended NiceHash and MRR profiles"
        return 0
    fi

    echo
    print_info "NiceHash and MiningRigRentals compatibility"
    print_info "These profiles apply to the selected Stratum: $SELECTED_STRATUM_BINARY"
    print_info "Press Enter to accept each recommended/current value."

    read -r -e -p "$nicehash_prompt" answer
    if [[ "$nicehash_enabled" == "y" ]]; then
        case "$answer" in
            n|N|no|NO) nicehash_enabled="n" ;;
        esac
    elif [[ "$answer" =~ ^([yY]|yes|YES)$ ]]; then
        nicehash_enabled="y"
    fi

    if [[ "$nicehash_enabled" == "y" ]]; then
        nicehash_initial="$(read_number_with_default "NiceHash initial difficulty" "$nicehash_initial")"
        nicehash_diff_min="$(read_number_with_default "NiceHash minimum difficulty" "$nicehash_diff_min")"
        nicehash_diff_max="$(read_number_with_default "NiceHash maximum difficulty" "$nicehash_diff_max")"

        number_le "$nicehash_diff_min" "$nicehash_initial" ||
            fatal "NiceHash minimum difficulty cannot exceed its initial difficulty"
        number_le "$nicehash_initial" "$nicehash_diff_max" ||
            fatal "NiceHash initial difficulty cannot exceed its maximum difficulty"
    fi

    read -r -e -p "Enable MiningRigRentals compatibility? (Y/n): " answer
    case "$answer" in
        n|N|no|NO) mrr_enabled="n" ;;
        *)
            mrr_initial="$(read_number_with_default "MRR initial difficulty" "$mrr_initial")"
            mrr_diff_min="$(read_number_with_default "MRR minimum difficulty" "$mrr_diff_min")"
            mrr_diff_max="$(read_number_with_default "MRR maximum difficulty" "$mrr_diff_max")"

            number_le "$mrr_diff_min" "$mrr_initial" ||
                fatal "MRR minimum difficulty cannot exceed its initial difficulty"
            number_le "$mrr_initial" "$mrr_diff_max" ||
                fatal "MRR initial difficulty cannot exceed its maximum difficulty"
            ;;
    esac
}

apply_marketplace_profiles() {
    local file="$1"

    if [[ "$nicehash_enabled" == "y" ]]; then
        upsert_simple_key "$file" "STRATUM" "nicehash" "$nicehash_initial"
        upsert_simple_key "$file" "STRATUM" "nicehash_diff_min" "$nicehash_diff_min"
        upsert_simple_key "$file" "STRATUM" "nicehash_diff_max" "$nicehash_diff_max"
    else
        remove_simple_key "$file" "STRATUM" "nicehash"
        remove_simple_key "$file" "STRATUM" "nicehash_diff_min"
        remove_simple_key "$file" "STRATUM" "nicehash_diff_max"
    fi

    if [[ "$mrr_enabled" == "y" ]]; then
        upsert_simple_key "$file" "STRATUM" "mrr" "$mrr_initial"
        upsert_simple_key "$file" "STRATUM" "mrr_diff_min" "$mrr_diff_min"
        upsert_simple_key "$file" "STRATUM" "mrr_diff_max" "$mrr_diff_max"
    else
        remove_simple_key "$file" "STRATUM" "mrr"
        remove_simple_key "$file" "STRATUM" "mrr_diff_min"
        remove_simple_key "$file" "STRATUM" "mrr_diff_max"
    fi
}

ensure_wallet_rule() {
    local file="$1"
    local rule="$2"
    local symbol="$3"

    if ! grep -Fqx "$rule = $symbol" "$file"; then
        printf '\n[WALLETS]\n%s = %s\n' "$rule" "$symbol" | sudo tee -a "$file" >/dev/null
    fi
}

get_config_port() {
    local file="$1"

    awk '
        BEGIN {
            in_tcp = 0
        }

        /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
            section = $0
            gsub(/^[[:space:]]*\[/, "", section)
            gsub(/\][[:space:]]*$/, "", section)
            in_tcp = (tolower(section) == "tcp")
            next
        }

        in_tcp && /^[[:space:]]*port[[:space:]]*=/ {
            value = $0
            sub(/^[^=]*=[[:space:]]*/, "", value)
            sub(/[[:space:]]*[;#].*$/, "", value)
            gsub(/[[:space:]]/, "", value)
            print value
            exit
        }
    ' "$file"
}

port_is_listening() {
    local port="$1"

    ss -ltnH 2>/dev/null \
        | awk '{print $4}' \
        | grep -Eq "(^|:)${port}$"
}

port_is_configured_elsewhere() {
    local port="$1"
    local exclude_config="${2:-}"
    local file
    local configured_port

    for file in "$CONFIG_DIR"/*.conf; do
        [ -f "$file" ] || continue

        if [ -n "$exclude_config" ] \
            && [ "$(readlink -f "$file")" = "$(readlink -f "$exclude_config")" ]; then
            continue
        fi

        configured_port=$(get_config_port "$file" || true)

        if [ "$configured_port" = "$port" ]; then
            printf '%s\n' "$file"
            return 0
        fi
    done

    return 1
}

port_is_available() {
    local port="$1"
    local exclude_config="${2:-}"
    local conflict=""

    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    if [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi

    if port_is_listening "$port"; then
        return 1
    fi

    conflict=$(port_is_configured_elsewhere \
        "$port" \
        "$exclude_config" || true)

    if [ -n "$conflict" ]; then
        return 1
    fi

    return 0
}

show_port_conflict() {
    local port="$1"
    local exclude_config="${2:-}"
    local conflict=""

    if port_is_listening "$port"; then
        print_warning "Port $port is currently in use by a listening service"
        return
    fi

    conflict=$(port_is_configured_elsewhere \
        "$port" \
        "$exclude_config" || true)

    if [ -n "$conflict" ]; then
        print_warning "Port $port is already configured in: $conflict"
        return
    fi

    print_warning "Port $port is not available"
}

choose_manual_port() {
    local exclude_config="${1:-}"
    local requested_port=""

    while true; do
        echo
        read -r -e -p \
            "Enter the Stratum port manually [1024-65535] or Q to cancel: " \
            requested_port

        case "$requested_port" in
            q|Q|quit|QUIT)
                return 1
                ;;
        esac

        if ! [[ "$requested_port" =~ ^[0-9]+$ ]]; then
            print_warning "Invalid port. Enter a numeric value."
            continue
        fi

        if [ "$requested_port" -lt 1024 ] \
            || [ "$requested_port" -gt 65535 ]; then
            print_warning "Port must be between 1024 and 65535"
            continue
        fi

        if ! port_is_available \
            "$requested_port" \
            "$exclude_config"; then

            show_port_conflict \
                "$requested_port" \
                "$exclude_config"

            continue
        fi

        coinport="$requested_port"
        print_success "Manual port selected: $coinport"
        return 0
    done
}

choose_new_port() {
    local exclude_config="${1:-}"
    local choice=""

    while true; do
        echo
        echo "Port selection:"
        echo "  1) Select an available port automatically"
        echo "  2) Enter a port manually"
        echo

        read -r -e -p "Select [1-2]: " choice

        case "$choice" in
            1|"")
                coinport=$(find_open_port)

                if port_is_available \
                    "$coinport" \
                    "$exclude_config"; then

                    print_success \
                        "Available port selected automatically: $coinport"
                    return 0
                fi

                print_warning \
                    "Automatically selected port $coinport is not available"
                ;;

            2)
                if choose_manual_port "$exclude_config"; then
                    return 0
                fi
                ;;

            *)
                print_warning "Invalid selection"
                ;;
        esac
    done
}

choose_existing_port() {
    local coin_config="$1"
    local current_port=""
    local choice=""

    current_port=$(get_config_port "$coin_config" || true)

    if ! [[ "$current_port" =~ ^[0-9]+$ ]] \
        || [ "$current_port" -lt 1 ] \
        || [ "$current_port" -gt 65535 ]; then

        print_warning \
            "No valid TCP port was found in the existing config"

        choose_new_port "$coin_config"
        return
    fi

    print_info "Current Stratum port: $current_port"

    if port_is_listening "$current_port"; then
        print_info "Port $current_port is currently listening"
    else
        print_info "Port $current_port is currently not listening"
    fi

    if [ "${CREATECOIN:-false}" = true ] && [ ! -t 0 ]; then
        coinport="$current_port"

        print_info \
            "Non-interactive mode: preserving existing port $coinport"

        return
    fi

    while true; do
        echo
        echo "Port options:"
        echo "  1) Keep current port $current_port"
        echo "  2) Select an available port automatically"
        echo "  3) Enter a port manually"
        echo

        read -r -e -p "Select [1-3] (default: 1): " choice

        case "$choice" in
            1|"")
                coinport="$current_port"
                print_success "Keeping existing port: $coinport"
                return
                ;;

            2)
                coinport=$(find_open_port)

                if port_is_available \
                    "$coinport" \
                    "$coin_config"; then

                    print_success \
                        "New available port selected automatically: $coinport"
                    return
                fi

                print_warning \
                    "Automatically selected port $coinport is not available"
                ;;

            3)
                if choose_manual_port "$coin_config"; then
                    return
                fi
                ;;

            *)
                print_warning "Invalid selection"
                ;;
        esac
    done
}

create_coin_config() {
    local base_config="$CONFIG_DIR/$SELECTED_ALGO.conf"
    local coin_config="$CONFIG_DIR/$coinsymbollower.$SELECTED_ALGO.conf"
    local existing=false
    local answer
    local other

    [ -f "$base_config" ] || fatal "Base algorithm config not found: $base_config"

    if [ -f "$coin_config" ]; then
        existing=true
        print_warning "Dedicated config already exists: $coin_config"

        if [ "${CREATECOIN:-false}" = true ] && [ ! -t 0 ]; then
            answer="y"
        else
            read -r -e -p                 "Update the existing Stratum configuration? (Y/n) : "                 answer
        fi

        case "$answer" in
            ""|y|Y|yes|YES)
                choose_existing_port "$coin_config"
                ;;
            *)
                print_info "No changes were made"
                exit 0
                ;;
        esac
    else
        choose_new_port
    fi

    if [ "$existing" = false ]; then
        shopt -s nullglob
        for other in "$CONFIG_DIR"/*."$SELECTED_ALGO".conf; do
            [ "$other" = "$coin_config" ] && continue
            ensure_wallet_rule "$other" "exclude" "$coinsymbol"
        done
        shopt -u nullglob

        sudo cp -a "$base_config" "$coin_config"
    fi

    upsert_simple_key "$coin_config" "TCP" "port" "$coinport"
    upsert_simple_key "$coin_config" "RUNTIME" "binary" "$SELECTED_STRATUM_BINARY"

    # Some stratum-kp builds strip ".conf" from KAWPOW configs.
    sqsyiimp_ensure_runtime_alias "$coin_config"

    local pool_coinbase_tag=""
    pool_coinbase_tag=$(get_pool_coinbase_tag || true)
    if [ -n "$pool_coinbase_tag" ]; then
        upsert_simple_key "$coin_config" "STRATUM" "coinbaseextra" "$pool_coinbase_tag"
    fi

    apply_marketplace_profiles "$coin_config"

    ensure_wallet_rule "$coin_config" "include" "$coinsymbol"
    ensure_wallet_rule "$base_config" "exclude" "$coinsymbol"

    CONFIG_PATH="$coin_config"
}

create_service_launcher() {
    local service_file="$SERVICE_DIR/$coinsymbollower.sh"
    local primary_command="/usr/bin/stratum.$coinsymbollower"
    local compatibility_command="/usr/bin/sqs-stratum-$coinsymbollower"

    sudo tee "$service_file" >/dev/null <<EOF_SERVICE
#!/usr/bin/env bash

if [[ -r /etc/yiimpool.conf ]]; then
    source /etc/yiimpool.conf
fi

STORAGE_USER="\${STORAGE_USER:-crypto-data}"
STORAGE_GROUP="\${STORAGE_GROUP:-\${STORAGE_USER}}"
STORAGE_ROOT="\${STORAGE_ROOT:-/home/\${STORAGE_USER}}"

if [[ -r /etc/default/sqsyiimp ]]; then
    source /etc/default/sqsyiimp
fi

if [[ -r "\$STORAGE_ROOT/yiimp/.yiimp.conf" ]]; then
    source "\$STORAGE_ROOT/yiimp/.yiimp.conf"
fi

STRATUM_USER="\${YIIMP_USER:-\$STORAGE_USER}"

STRATUM_DIR="\$STORAGE_ROOT/yiimp/site/stratum"
RUNNER="\$STRATUM_DIR/runner.sh"

SESSION="$coinsymbollower"
CONFIG="$coinsymbollower.$SELECTED_ALGO.conf"


stratum_as_runtime() {
    if [[ "\$(id -un)" == "\$STRATUM_USER" ]]; then
        "\$@"
    else
        sudo -u "\$STRATUM_USER" -H "\$@"
    fi
}


screen_running() {
    stratum_as_runtime screen -ls 2>/dev/null |
        grep -Eq "[.]\${SESSION}[[:space:]]"
}


start_service() {
    if ! command -v screen >/dev/null 2>&1; then
        echo "ERROR: screen is required to start Stratum services" >&2
        return 127
    fi

    if screen_running; then
        echo "Stratum session already running: \$SESSION"
        return 0
    fi

    stratum_as_runtime \
        screen -dmS "\$SESSION" \
        "\$RUNNER" "\$CONFIG"
}


stop_service() {
    if ! screen_running; then
        echo "Stratum session is not running: \$SESSION"
        return 0
    fi

    stratum_as_runtime \
        screen -S "\$SESSION" -X quit \
        2>/dev/null || true
}


case "\${1:-}" in
    start)
        start_service
        ;;

    stop)
        stop_service
        ;;

    restart)
        stop_service
        sleep 1
        start_service
        ;;

    status)
        if screen_running; then
            echo "RUNNING: \$SESSION"
            exit 0
        fi

        echo "STOPPED: \$SESSION"
        exit 1
        ;;

    *)
        echo "Usage: \$0 {start|stop|restart|status}"
        exit 1
        ;;
esac
EOF_SERVICE

    sudo chown root:root "$service_file"
    sudo chmod 755 "$service_file"

    sudo cp "$service_file" "$primary_command"
    sudo chown root:root "$primary_command"
    sudo chmod 755 "$primary_command"

    sudo ln -sfn \
        "$primary_command" \
        "$compatibility_command"

    SERVICE_COMMAND="$primary_command"
}


register_autostart() {
    local marker="stratum.$coinsymbollower start"
    local compatibility_marker="sqs-stratum-$coinsymbollower start"
    local runtime_user="${STORAGE_USER:-crypto-data}"
    local current_user=""
    local log_file=""
    local YIIMP_USER=""

    if ! command -v crontab >/dev/null 2>&1; then
        print_warning \
            "crontab is not available; Stratum autostart was not registered"
        return 0
    fi

    if [[ -r /etc/default/sqsyiimp ]]; then
        source /etc/default/sqsyiimp
        runtime_user="${YIIMP_USER:-$runtime_user}"
    fi

    if ! id "$runtime_user" >/dev/null 2>&1; then
        print_warning "Runtime user does not exist: $runtime_user"
        return 1
    fi

    current_user="$(id -un)"

    log_file="$STORAGE_ROOT/yiimp/site/log/stratum-${coinsymbollower}-boot.log"

    #
    # Remove legacy autostart for this coin from the current
    # administrator account during migration.
    #
    if [[ "$current_user" != "$runtime_user" ]]; then
        {
            crontab -l 2>/dev/null |
                grep -vF "$marker" |
                grep -vF "$compatibility_marker" ||
                true
        } | crontab -
    fi

    #
    # Register exactly one entry under the runtime user.
    #
    if [[ "$current_user" == "$runtime_user" ]]; then

        {
            crontab -l 2>/dev/null |
                grep -vF "$marker" |
                grep -vF "$compatibility_marker" ||
                true

            printf \
                '@reboot sleep 30 && %s start >> %s 2>&1\n' \
                "$SERVICE_COMMAND" \
                "$log_file"

        } | crontab -

    else

        {
            sudo -u "$runtime_user" crontab -l 2>/dev/null |
                grep -vF "$marker" |
                grep -vF "$compatibility_marker" ||
                true

            printf \
                '@reboot sleep 30 && %s start >> %s 2>&1\n' \
                "$SERVICE_COMMAND" \
                "$log_file"

        } | sudo -u "$runtime_user" crontab -

    fi

    print_info \
        "Stratum autostart registered for user: $runtime_user"
}


save_createcoin_result() {
    sudo tee "$STORAGE_ROOT/daemon_builder/.addport.cnf" >/dev/null <<EOF_RESULT
COINPORT='$coinport'
COINALGO='$SELECTED_ALGO'
STRATUMBINARY='$SELECTED_STRATUM_BINARY'
STRATUMCONFIG='$CONFIG_PATH'
EOF_RESULT
}

show_summary() {
    print_divider
    print_header "Stratum Configuration Complete"
    print_success "Dedicated Stratum configuration created successfully"
    print_info "Coin           : $coinsymbol"
    print_info "Algorithm      : $SELECTED_ALGO"
    print_info "Port           : $coinport"
    print_info "Binary         : $SELECTED_STRATUM_BINARY"
    print_info "Config         : $CONFIG_PATH"
    print_info "Service command: $SERVICE_COMMAND"
    print_info "Screen session : $coinsymbollower"
    if [[ "${nicehash_enabled:-n}" == "y" ]]; then
        print_info "NiceHash       : enabled (initial=$nicehash_initial, min=$nicehash_diff_min, max=$nicehash_diff_max)"
    else
        print_info "NiceHash       : disabled"
    fi
    if [[ "${mrr_enabled:-n}" == "y" ]]; then
        print_info "MRR            : enabled (initial=$mrr_initial, min=$mrr_diff_min, max=$mrr_diff_max)"
    else
        print_info "MRR            : disabled"
    fi
    echo
    print_info "Start   : $SERVICE_COMMAND start"
    print_info "Stop    : $SERVICE_COMMAND stop"
    print_info "Restart : $SERVICE_COMMAND restart"
    print_info "Status  : $SERVICE_COMMAND status"
    print_info "Console : sudo -u ${STORAGE_USER:-crypto-data} -H screen -r $coinsymbollower"
    print_divider
}

main() {
    local mode="${1:-}"
    local requested_algo=""
    local requested_binary=""

    ensure_layout
    ensure_sha256d_template

    case "$mode" in

        --refresh-wrapper)
            refresh_coin="${2,,}"

            [[ "$refresh_coin" =~ ^[a-z0-9_-]+$ ]] ||                 fatal "Usage: addport --refresh-wrapper COIN"

            sqsyiimp_refresh_stratum_wrappers "$refresh_coin"

            print_success                 "Managed Stratum wrapper refreshed: $refresh_coin"

            exit 0
            ;;

        --refresh-wrappers)
            sqsyiimp_refresh_stratum_wrappers

            print_success                 "All eligible managed Stratum wrappers were refreshed"

            exit 0
            ;;

        --stratums|-s|--list-stratums|--list-binaries)
            print_manager_header
            echo
            print_info "Available Stratum binaries:"
            while IFS= read -r item; do
                [ -n "$item" ] || continue
                printf '  %-32s %s\n' "$item" "$(binary_description "$item")"
            done < <(list_stratum_binaries | sort -u)
            exit 0
            ;;
        --algos|-a|--list-algorithms|--list-algos)
            print_manager_header
            echo
            print_info "Available algorithm templates:"
            list_algorithms | sed 's/^/  /'
            exit 0
            ;;
        -h|--help)
            cat <<'EOF_HELP'
Usage:
  addport
  addport <SYMBOL> <ALGO> [STRATUM_BINARY]
  addport --stratums
  addport --algos
  addport --refresh-wrapper COIN
  addport --refresh-wrappers

Examples:
  addport GAEL kawpow stratum-kawpow
  addport --stratums
  addport --algos

The selected executable is stored in the generated config as:

[RUNTIME]
binary = <stratum-binary>
EOF_HELP
            exit 0
            ;;
    esac

    clear 2>/dev/null || true
    print_manager_header

    if [ "$mode" = "CREATECOIN" ]; then
        # Backward-compatible non-interactive syntax.
        CREATECOIN=true
        coinsymbol="${2:-}"
        requested_algo="${3:-}"
        requested_binary="${4:-}"
        [ -n "$coinsymbol" ] || fatal "CREATECOIN requires a coin symbol"
        print_info "Creating a dedicated Stratum port for ${coinsymbol^^}"
    elif [ -n "$mode" ]; then
        # Simple syntax: addport SYMBOL ALGO [STRATUM_BINARY]
        CREATECOIN=true
        coinsymbol="$mode"
        requested_algo="${2:-}"
        requested_binary="${3:-}"
        [ -n "$requested_algo" ] || fatal "Algorithm is required. Example: addport GAEL kawpow stratum-kawpow"
        print_info "Creating a dedicated Stratum port for ${coinsymbol^^}"
    else
        CREATECOIN=false
        read -r -e -p "Please enter the coin SYMBOL: " coinsymbol
        [ -n "$coinsymbol" ] || fatal "Coin symbol cannot be empty"
    fi

    coinsymbol=${coinsymbol^^}
    coinsymbollower=${coinsymbol,,}

    select_algorithm "$requested_algo"
    select_stratum_binary "$requested_binary"

    echo
    print_success "Selected algorithm: $SELECTED_ALGO"
    print_success "Selected Stratum : $SELECTED_STRATUM_BINARY"
    echo

    configure_marketplace_profiles

    coinport=""
    create_coin_config

    if [ -x "$RUNNER" ]; then
        if ! "$RUNNER" --resolve "${CONFIG_PATH##*/}" >/dev/null; then
            fatal "Generated config could not resolve its selected Stratum binary"
        fi
    else
        print_warning "Stratum runner not found yet: $RUNNER"
    fi

    create_service_launcher

    # Convert only this coin to the managed health-check wrapper.
    # Do not rewrite unrelated Stratum services.
    sqsyiimp_refresh_stratum_wrappers "$coinsymbollower"

    sudo ufw allow "$coinport" >/dev/null 2>&1 || print_warning "Unable to add UFW rule for port $coinport"

    #
    # Stop only the Stratum service managed for this coin.
    # Never kill arbitrary processes merely because they own
    # the selected TCP port.
    #
    print_info "Stopping any existing managed Stratum service..."

    if ! "$SERVICE_COMMAND" stop; then
        print_warning "Existing Stratum could not be stopped cleanly"
        print_warning "Automatic start aborted to prevent a duplicate process"
        return 1 2>/dev/null || exit 1
    fi

    #
    # After the managed service has stopped, the selected port
    # must really be free. If another process owns it, abort.
    #
    if ! free_stratum_port "${coinport}"; then
        echo "ERROR: Cannot start Stratum because port ${coinport} is occupied"
        return 1 2>/dev/null || exit 1
    fi

    print_info "Starting the new Stratum service..."

    if "$SERVICE_COMMAND" start; then
        print_success "Stratum service started"

        if register_autostart; then
            print_success "Stratum autostart registered"
        else
            print_warning "Stratum started, but autostart could not be registered"
        fi
    else
        print_warning "Stratum service could not be started automatically; the config and service command were still created"
    fi

    if [ "$CREATECOIN" = true ]; then
        save_createcoin_result
    fi

    show_summary
}

main "$@"
