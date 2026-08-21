#!/usr/bin/env bash

############################################################
# Install Stratum management tools
# SabiasQue.Space
############################################################

set -euo pipefail

if [ -f /etc/yiimpool.conf ]; then
    source /etc/yiimpool.conf
fi

STORAGE_USER="${STORAGE_USER:-crypto-data}"
STORAGE_GROUP="${STORAGE_GROUP:-${STORAGE_USER}}"
STORAGE_ROOT="${STORAGE_ROOT:-/home/${STORAGE_USER}}"
STRATUM_DIR="$STORAGE_ROOT/yiimp/site/stratum"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANAGER_SOURCE="$SCRIPT_DIR/addport.sh"
RUNTIME_INSTALLER="$SCRIPT_DIR/install-runtime.sh"

[ -f "$MANAGER_SOURCE" ] || {
    echo "ERROR: Stratum port manager source not found: $MANAGER_SOURCE" >&2
    exit 1
}

[ -f "$RUNTIME_INSTALLER" ] || {
    echo "ERROR: Stratum runtime installer not found: $RUNTIME_INSTALLER" >&2
    exit 1
}

bash "$RUNTIME_INSTALLER" "$STRATUM_DIR"

sudo cp "$MANAGER_SOURCE" /usr/bin/addport
sudo chmod 755 /usr/bin/addport
sudo ln -sfn /usr/bin/addport /usr/bin/sqs-stratum-port

if [ -d "$STORAGE_ROOT/daemon_builder" ]; then
    sudo install         -o "$STORAGE_USER"         -g "$STORAGE_GROUP"         -m 755         "$MANAGER_SOURCE"         "$STORAGE_ROOT/daemon_builder/addport.sh"
fi

echo "Stratum tools installed successfully."
echo "Primary command: addport"
echo "Compatibility command: sqs-stratum-port"
echo
echo "Available Stratum binaries:"
/usr/bin/addport --stratums || true
