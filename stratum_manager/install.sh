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
REMOVE_SOURCE="$SCRIPT_DIR/removecoin.sh"
RUNTIME_INSTALLER="$SCRIPT_DIR/install-runtime.sh"
ETHASH_TEMPLATE_SOURCE="$SCRIPT_DIR/templates/ethash.conf"

[ -f "$MANAGER_SOURCE" ] || {
    echo "ERROR: Stratum port manager source not found: $MANAGER_SOURCE" >&2
    exit 1
}

[ -f "$RUNTIME_INSTALLER" ] || {
    echo "ERROR: Stratum runtime installer not found: $RUNTIME_INSTALLER" >&2
    exit 1
}

[ -f "$REMOVE_SOURCE" ] || {
    echo "ERROR: Coin removal manager source not found: $REMOVE_SOURCE" >&2
    exit 1
}

[ -f "$ETHASH_TEMPLATE_SOURCE" ] || {
    echo "ERROR: Ethash Stratum template not found: $ETHASH_TEMPLATE_SOURCE" >&2
    exit 1
}

install_ethash_templates() {
    local base_target="$STRATUM_DIR/config/ethash.conf"
    local vbc_target="$STRATUM_DIR/config/vbc.ethash.conf"
    local yiimp_conf="$STORAGE_ROOT/yiimp/.yiimp.conf"
    local db_host="localhost"
    local rendered=""
    local base_rendered=""

    if [[ -f "$base_target" && -f "$vbc_target" ]]; then
        echo "Ethash Stratum templates already exist; preserving administrator configuration"
        return 0
    fi

    if [[ -r "$yiimp_conf" ]]; then
        # shellcheck disable=SC1090
        source "$yiimp_conf"
    fi

    if [[ -z "${StratumURL:-}" ||
          -z "${BlocknotifyPassword:-}" ||
          -z "${YiiMPDBName:-}" ||
          -z "${StratumDBUser:-}" ||
          -z "${StratumUserDBPassword:-}" ]]; then
        echo "WARNING: Ethash templates were not installed because SQSYIIMP credentials are incomplete in $yiimp_conf" >&2
        return 0
    fi

    # DBInternalIP is persisted only for remote/WireGuard DB installs.
    # Local MegaHashPool installs therefore keep the requested localhost host.
    if [[ -n "${DBInternalIP:-}" ]]; then
        db_host="$DBInternalIP"
    fi

    rendered="$(mktemp)"
    base_rendered="$(mktemp)"
    cp "$ETHASH_TEMPLATE_SOURCE" "$rendered"

    STRATUM_URL="$StratumURL" \
    STRATUM_PASSWORD="$BlocknotifyPassword" \
    SQL_HOST="$db_host" \
    SQL_DATABASE="$YiiMPDBName" \
    SQL_USERNAME="$StratumDBUser" \
    SQL_PASSWORD="$StratumUserDBPassword" \
    python3 - "$rendered" "$base_rendered" <<'PY_RENDER_ETHASH'
import os
import re
import sys
from pathlib import Path

vbc_path = Path(sys.argv[1])
base_path = Path(sys.argv[2])
text = vbc_path.read_text()

replacements = {
    ("TCP", "server"): os.environ["STRATUM_URL"],
    ("TCP", "password"): os.environ["STRATUM_PASSWORD"],
    ("SQL", "host"): os.environ["SQL_HOST"],
    ("SQL", "database"): os.environ["SQL_DATABASE"],
    ("SQL", "username"): os.environ["SQL_USERNAME"],
    ("SQL", "password"): os.environ["SQL_PASSWORD"],
}

section = None
vbc_lines = []
base_lines = []
for line in text.splitlines():
    match = re.match(r"^\s*\[([^]]+)\]\s*$", line)
    if match:
        section = match.group(1).upper()
        vbc_lines.append(line)
        base_lines.append(line)
        continue

    rendered = line
    for (wanted_section, key), value in replacements.items():
        if section == wanted_section and re.match(rf"^\s*{re.escape(key)}\s*=", line, re.I):
            rendered = f"{key} = {value}"
            break

    vbc_lines.append(rendered)

    # The base algorithm template must remain coin-neutral. addport will add
    # the requested wallet include to each dedicated <coin>.ethash.conf.
    if section == "WALLETS" and re.match(r"^\s*include\s*=", rendered, re.I):
        continue
    base_lines.append(rendered)

vbc_path.write_text("\n".join(vbc_lines) + "\n")
base_path.write_text("\n".join(base_lines) + "\n")
PY_RENDER_ETHASH

    if [[ ! -f "$base_target" ]]; then
        sudo install \
            -o "$STORAGE_USER" \
            -g "$STORAGE_GROUP" \
            -m 0640 \
            "$base_rendered" \
            "$base_target"
        echo "Ethash base algorithm template installed: $base_target"
    else
        echo "Ethash base template already exists; preserving: $base_target"
    fi

    if [[ ! -f "$vbc_target" ]]; then
        sudo install \
            -o "$STORAGE_USER" \
            -g "$STORAGE_GROUP" \
            -m 0640 \
            "$rendered" \
            "$vbc_target"
        echo "VBC Ethash Stratum configuration installed: $vbc_target"
    else
        echo "VBC Ethash config already exists; preserving: $vbc_target"
    fi

    rm -f "$rendered" "$base_rendered"
}

sudo install -d \
    -o "$STORAGE_USER" \
    -g "$STORAGE_GROUP" \
    -m 0755 \
    "$STRATUM_DIR/config"

install_ethash_templates
bash "$RUNTIME_INSTALLER" "$STRATUM_DIR"

sudo cp "$MANAGER_SOURCE" /usr/bin/addport
sudo chmod 755 /usr/bin/addport
sudo ln -sfn /usr/bin/addport /usr/bin/sqs-stratum-port

sudo install -o root -g root -m 0755 "$REMOVE_SOURCE" /usr/bin/removecoin
sudo ln -sfn /usr/bin/removecoin /usr/bin/sqs-remove-coin

if [ -d "$STORAGE_ROOT/daemon_builder" ]; then
    sudo install         -o "$STORAGE_USER"         -g "$STORAGE_GROUP"         -m 755         "$MANAGER_SOURCE"         "$STORAGE_ROOT/daemon_builder/addport.sh"
fi

echo "Stratum tools installed successfully."
echo "Primary Stratum command: addport"
echo "Coin removal command   : removecoin"
echo "Compatibility commands : sqs-stratum-port, sqs-remove-coin"
echo
echo "Available Stratum binaries:"
/usr/bin/addport --stratums || true
