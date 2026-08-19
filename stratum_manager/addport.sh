#!/usr/bin/env bash

# === MEGAHASHPOOL FREE STRATUM PORT ===
free_stratum_port() {
    local port="$1"

    if [[ -z "$port" ]]; then
        echo "ERROR: Stratum port is empty"
        return 1
    fi

    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo "ERROR: Invalid Stratum port: $port"
        return 1
    fi

    echo "INFO: Checking Stratum port $port..."

    # ¿Está escuchando?
    if ! sudo ss -lntp 2>/dev/null | grep -qE ":${port}[[:space:]]"; then
        echo "SUCCESS: Port $port is available"
        return 0
    fi

    echo "WARNING: Port $port is currently in use"

    local pids

    pids=$(
        sudo ss -lntp 2>/dev/null |
        grep -E ":${port}[[:space:]]" |
        grep -oE 'pid=[0-9]+' |
        cut -d= -f2 |
        sort -u
    )

    if [[ -z "$pids" ]]; then
        echo "ERROR: Port $port is busy but PID could not be detected"
        sudo ss -lntp 2>/dev/null | grep -E ":${port}[[:space:]]" || true
        return 1
    fi

    echo "INFO: Process(es) using port $port: $pids"

    local pid
    local cmd

    for pid in $pids; do
        cmd=$(ps -p "$pid" -o args= 2>/dev/null || true)

        echo "INFO: PID $pid"
        echo "INFO: Command: $cmd"
        echo "INFO: Sending SIGTERM to PID $pid"

        sudo kill -TERM "$pid" 2>/dev/null || true
    done

    # Esperar hasta 5 segundos
    local n

    for n in 1 2 3 4 5; do
        sleep 1

        if ! sudo ss -lntp 2>/dev/null | grep -qE ":${port}[[:space:]]"; then
            echo "SUCCESS: Port $port has been released"
            return 0
        fi

        echo "INFO: Waiting for port $port to be released... ($n/5)"
    done

    echo "WARNING: Port $port is still in use"

    pids=$(
        sudo ss -lntp 2>/dev/null |
        grep -E ":${port}[[:space:]]" |
        grep -oE 'pid=[0-9]+' |
        cut -d= -f2 |
        sort -u
    )

    if [[ -n "$pids" ]]; then
        echo "WARNING: Force killing process(es): $pids"

        for pid in $pids; do
            sudo kill -KILL "$pid" 2>/dev/null || true
        done
    fi

    sleep 1

    if sudo ss -lntp 2>/dev/null | grep -qE ":${port}[[:space:]]"; then
        echo "ERROR: Could not release port $port"
        sudo ss -lntp 2>/dev/null | grep -E ":${port}[[:space:]]" || true
        return 1
    fi

    echo "SUCCESS: Port $port is now available"
    return 0
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

    local pool_coinbase_tag=""
    pool_coinbase_tag=$(get_pool_coinbase_tag || true)
    if [ -n "$pool_coinbase_tag" ]; then
        upsert_simple_key "$coin_config" "STRATUM" "coinbaseextra" "$pool_coinbase_tag"
    fi

    if [[ "${nicehash:-n}" =~ ^([yY]|yes|YES)$ ]]; then
        upsert_simple_key "$coin_config" "STRATUM" "nicehash" "$nicevalue"
    else
        remove_simple_key "$coin_config" "STRATUM" "nicehash"
    fi

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

source /etc/yiimpool.conf
source "\$STORAGE_ROOT/yiimp/.yiimp.conf"

STRATUM_DIR="\$STORAGE_ROOT/yiimp/site/stratum"
RUNNER="\$STRATUM_DIR/runner.sh"
SESSION="$coinsymbollower"
CONFIG="$coinsymbollower.$SELECTED_ALGO.conf"

start_service() {
    if ! command -v screen >/dev/null 2>&1; then
        echo "ERROR: screen is required to start Stratum services" >&2
        return 127
    fi
    if screen -ls 2>/dev/null | grep -Eq "[.]\${SESSION}[[:space:]]"; then
        echo "Stratum session already running: \$SESSION"
        return 0
    fi
    screen -dmS "\$SESSION" "\$RUNNER" "\$CONFIG"
}

stop_service() {
    screen -S "\$SESSION" -X quit 2>/dev/null || true
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
        if screen -ls 2>/dev/null | grep -Eq "[.]\${SESSION}[[:space:]]"; then
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

    sudo chmod 755 "$service_file"
    sudo cp "$service_file" "$primary_command"
    sudo chmod 755 "$primary_command"
    sudo ln -sfn "$primary_command" "$compatibility_command"

    SERVICE_COMMAND="$primary_command"
}

register_autostart() {
    local marker="stratum.$coinsymbollower start"
    local tmp

    if ! command -v crontab >/dev/null 2>&1; then
        print_warning "crontab is not available; Stratum autostart was not registered"
        return 0
    fi

    tmp=$(mktemp)
    crontab -l 2>/dev/null | grep -vF "$marker" | grep -vF "sqs-stratum-$coinsymbollower start" >"$tmp" || true
    printf '@reboot sleep 30 && %s start >> /var/log/stratum-%s-boot.log 2>&1\n' \
        "$SERVICE_COMMAND" "$coinsymbollower" >>"$tmp"
    crontab "$tmp"
    rm -f "$tmp"
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
    echo
    print_info "Start   : $SERVICE_COMMAND start"
    print_info "Stop    : $SERVICE_COMMAND stop"
    print_info "Restart : $SERVICE_COMMAND restart"
    print_info "Status  : $SERVICE_COMMAND status"
    print_info "Console : screen -r $coinsymbollower"
    print_divider
}

main() {
    local mode="${1:-}"
    local requested_algo=""
    local requested_binary=""

    ensure_layout

    case "$mode" in
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

    nicehash="n"
    if [ -t 0 ]; then
        read -r -e -p "Would you like to set a minimum NiceHash value? (y/n) : " nicehash
        if [[ "$nicehash" =~ ^([yY]|yes|YES)$ ]]; then
            read -r -e -p "Please enter a whole value, example 750000: " nicevalue
            [[ "$nicevalue" =~ ^[0-9]+$ ]] || fatal "NiceHash value must be a positive whole number"
        fi
    fi

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
    sudo ufw allow "$coinport" >/dev/null 2>&1 || print_warning "Unable to add UFW rule for port $coinport"
    register_autostart

    # === RELEASE STRATUM PORT BEFORE START ===
    #
    # coinport is the final selected port. current_port only
    # exists locally inside choose_existing_port().
    #
    if ! free_stratum_port "${coinport}"; then
        echo "ERROR: Cannot start Stratum: port ${coinport} could not be released"
        return 1 2>/dev/null || exit 1
    fi
    # === END RELEASE STRATUM PORT ===

    print_info "Starting the new Stratum service..."
    if "$SERVICE_COMMAND" restart; then
        print_success "Stratum service started"
    else
        print_warning "Stratum service could not be started automatically; the config and service command were still created"
    fi

    if [ "$CREATECOIN" = true ]; then
        save_createcoin_result
    fi

    show_summary
}

main "$@"
