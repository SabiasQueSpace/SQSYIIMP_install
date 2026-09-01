#!/usr/bin/env bash

############################################################
# Install Stratum runtime helpers
# SabiasQue.Space
############################################################

set -euo pipefail

if [ -f /etc/yiimpool.conf ]; then
    source /etc/yiimpool.conf
fi

STORAGE_USER="${STORAGE_USER:-crypto-data}"
STORAGE_GROUP="${STORAGE_GROUP:-${STORAGE_USER}}"
STORAGE_ROOT="${STORAGE_ROOT:-/home/${STORAGE_USER}}"

STRATUM_DIR="${1:-${STORAGE_ROOT}/yiimp/site/stratum}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER_SOURCE="$SCRIPT_DIR/runner.sh"

if [ ! -f "$RUNNER_SOURCE" ]; then
    echo "ERROR: Stratum runner source not found: $RUNNER_SOURCE" >&2
    exit 1
fi

sudo install -d     -o "$STORAGE_USER"     -g "$STORAGE_GROUP"     -m 755     "$STRATUM_DIR"     "$STRATUM_DIR/config"     "$STRATUM_DIR/services"

sudo install     -o "$STORAGE_USER"     -g "$STORAGE_GROUP"     -m 755     "$RUNNER_SOURCE"     "$STRATUM_DIR/runner.sh"

# Persistent per-coin Stratum logs. Existing configurations are migrated
# here; newly-created configurations are handled by addport as well.
shopt -s nullglob
for config_file in "$STRATUM_DIR"/config/*.conf; do
    config_name="${config_file##*/}"
    coin_name="${config_name%%.*}"
    if [[ "$coin_name" =~ ^[A-Za-z0-9_-]+$ ]]; then
        sudo touch "/var/log/stratum-${coin_name}.log"
        sudo chown "$STORAGE_USER:$STORAGE_GROUP" "/var/log/stratum-${coin_name}.log"
        sudo chmod 0640 "/var/log/stratum-${coin_name}.log"
        if command -v setfacl >/dev/null 2>&1 && \
           [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
            sudo setfacl -m "u:${SUDO_USER}:rw,m::rw" \
                "/var/log/stratum-${coin_name}.log"
        fi
    fi
done
shopt -u nullglob

sudo tee /etc/logrotate.d/sqsyiimp-stratum >/dev/null <<EOF_LOGROTATE
/var/log/stratum-*.log {
    daily
    rotate 7
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
    dateext
    create 0640 ${STORAGE_USER} ${STORAGE_GROUP}
    postrotate
        /usr/bin/chown ${STORAGE_USER}:${STORAGE_GROUP} /var/log/stratum-*.log 2>/dev/null || true
        /usr/bin/chmod 0640 /var/log/stratum-*.log 2>/dev/null || true
        if [ -x /usr/bin/setfacl ] && [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER:-root}" != root ]; then
            /usr/bin/setfacl -m u:${SUDO_USER}:rw,m::rw /var/log/stratum-*.log 2>/dev/null || true
        fi
    endscript
}
EOF_LOGROTATE
sudo chown root:root /etc/logrotate.d/sqsyiimp-stratum
sudo chmod 0644 /etc/logrotate.d/sqsyiimp-stratum

# Migrate pre-existing per-coin launchers. Older launchers created GNU Screen
# sessions as whichever administrator invoked them. Keep their service logic,
# but replace the public command with a wrapper that always delegates to the
# configured YiiMP runtime account. During stop/restart it also removes a
# legacy session owned by the invoking administrator.
shopt -s nullglob
for launcher in /usr/bin/stratum.*; do
    coin_name="${launcher##*.}"
    [[ "$coin_name" =~ ^[A-Za-z0-9_-]+$ ]] || continue
    config_matches=("$STRATUM_DIR/config/${coin_name}."*.conf)
    ((${#config_matches[@]} > 0)) || continue

    service_launcher="$STRATUM_DIR/services/${coin_name}.sh"
    if [ ! -f "$service_launcher" ]; then
        sudo install -o root -g root -m 0755 "$launcher" "$service_launcher"
    fi

    sudo tee "$launcher" >/dev/null <<EOF_LAUNCHER
#!/usr/bin/env bash

set -u

source /etc/yiimpool.conf
[ -r "\${STORAGE_ROOT}/yiimp/.yiimp.conf" ] && source "\${STORAGE_ROOT}/yiimp/.yiimp.conf"
[ -r /etc/default/sqsyiimp ] && source /etc/default/sqsyiimp

STRATUM_USER="\${YIIMP_USER:-\${STORAGE_USER:-crypto-data}}"
SESSION="${coin_name}"
SERVICE_LAUNCHER="${service_launcher}"
ACTION="\${1:-}"

if [ "\$(id -un)" != "\$STRATUM_USER" ]; then
    if /usr/bin/screen -ls 2>/dev/null | grep -Eq "[.]\${SESSION}[[:space:]]"; then
        case "\$ACTION" in
            stop|restart)
                /usr/bin/screen -S "\$SESSION" -X quit 2>/dev/null || true
                sleep 1
                ;;
            start)
                echo "ERROR: legacy screen '\$SESSION' belongs to \$(id -un)." >&2
                echo "Run: \$0 restart" >&2
                exit 1
                ;;
        esac
    fi
    exec sudo -u "\$STRATUM_USER" -H "\$SERVICE_LAUNCHER" "\$@"
fi

exec "\$SERVICE_LAUNCHER" "\$@"
EOF_LAUNCHER
    sudo chown root:root "$launcher"
    sudo chmod 0755 "$launcher"
done
shopt -u nullglob

sudo tee "$STRATUM_DIR/stratum-runner.sh" >/dev/null <<'EOF_COMPAT_RUNNER'
#!/usr/bin/env bash
exec "$(cd "$(dirname "$0")" && pwd)/runner.sh" "$@"
EOF_COMPAT_RUNNER
sudo chown "$STORAGE_USER:$STORAGE_GROUP" "$STRATUM_DIR/stratum-runner.sh"
sudo chmod 755 "$STRATUM_DIR/stratum-runner.sh"

sudo tee "$STRATUM_DIR/run.sh" >/dev/null <<'EOF_WRAPPER'
#!/usr/bin/env bash
source /etc/yiimpool.conf
source "$STORAGE_ROOT/yiimp/.yiimp.conf"
exec "$STORAGE_ROOT/yiimp/site/stratum/runner.sh" "$@"
EOF_WRAPPER
sudo chown "$STORAGE_USER:$STORAGE_GROUP" "$STRATUM_DIR/run.sh"
sudo chmod 755 "$STRATUM_DIR/run.sh"

sudo tee "$STRATUM_DIR/config/run.sh" >/dev/null <<'EOF_CONFIG_WRAPPER'
#!/usr/bin/env bash
source /etc/yiimpool.conf
source "$STORAGE_ROOT/yiimp/.yiimp.conf"
exec "$STORAGE_ROOT/yiimp/site/stratum/runner.sh" "$@"
EOF_CONFIG_WRAPPER
sudo chown "$STORAGE_USER:$STORAGE_GROUP" "$STRATUM_DIR/config/run.sh"
sudo chmod 755 "$STRATUM_DIR/config/run.sh"

printf 'Stratum runtime installed in %s\n' "$STRATUM_DIR"
printf 'Stratum logs: /var/log/stratum-<coin>.log (7 daily rotations)\n'
