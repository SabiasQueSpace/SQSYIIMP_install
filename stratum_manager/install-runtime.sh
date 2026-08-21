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
