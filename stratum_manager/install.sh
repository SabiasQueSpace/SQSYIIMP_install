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
CONFIG_DIR="$STRATUM_DIR/config"
TEMPLATE_DIR="$CONFIG_DIR/templates"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANAGER_SOURCE="$SCRIPT_DIR/addport.sh"
REMOVE_SOURCE="$SCRIPT_DIR/removecoin.sh"
RUNTIME_INSTALLER="$SCRIPT_DIR/install-runtime.sh"
SHA3X_TEMPLATE_SOURCE="$SCRIPT_DIR/templates/sha3x.conf"

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


[ -f "$SHA3X_TEMPLATE_SOURCE" ] || {
    echo "ERROR: SHA3X Stratum template not found: $SHA3X_TEMPLATE_SOURCE" >&2
    exit 1
}

migrate_legacy_algorithm_templates() {
    local source=""
    local name=""
    local stem=""
    local target=""
    local legacy_alias=""
    local template_alias=""
    local alias_target=""

    #
    # Remove deprecated COSA/Cosanta artifacts from legacy installations.
    # Exact names only.
    #
    for name in cosa.conf cosanta.conf; do
        stem="${name%.conf}"

        sudo rm -f -- \
            "$CONFIG_DIR/$name" \
            "$CONFIG_DIR/$stem" \
            "$TEMPLATE_DIR/$name" \
            "$TEMPLATE_DIR/$stem"
    done

    sudo install -d \
        -o "$STORAGE_USER" \
        -g "$STORAGE_GROUP" \
        -m 0755 \
        "$TEMPLATE_DIR"

    shopt -s nullglob
    for source in "$CONFIG_DIR"/*.conf; do
        name="${source##*/}"
        stem="${name%.conf}"

        # Dedicated coin configs contain at least one dot before .conf
        # (for example btc.sha256d.conf or vbc.ethash.conf).  The old
        # addport algorithm catalogue intentionally used only one-part
        # names such as sha256d.conf, kawpow.conf and x11.conf.
        [[ "$stem" == *.* ]] && continue

        target="$TEMPLATE_DIR/$name"

        if [[ ! -e "$target" ]]; then
            sudo mv "$source" "$target"
            sudo chown "$STORAGE_USER:$STORAGE_GROUP" "$target"
            echo "Moved Stratum algorithm template: $name -> config/templates/"
        elif sudo cmp -s "$source" "$target"; then
            sudo rm -f "$source"
            sudo chown "$STORAGE_USER:$STORAGE_GROUP" "$target"
            echo "Removed duplicate legacy template: $source"
        else
            echo "WARNING: template exists in both locations with different contents:" >&2
            echo "         legacy: $source" >&2
            echo "         active: $target" >&2
            echo "         preserving both; resolve manually before deleting the legacy copy" >&2
            continue
        fi

        # Move the optional suffix-less compatibility alias with its template.
        # Dedicated coin aliases contain a dot in their stem and never reach
        # this branch.
        legacy_alias="$CONFIG_DIR/$stem"
        template_alias="$TEMPLATE_DIR/$stem"

        if [[ -L "$legacy_alias" ]]; then
            alias_target="$(readlink "$legacy_alias" 2>/dev/null || true)"
            if [[ "$alias_target" == "$name" ||
                  "$alias_target" == "$CONFIG_DIR/$name" ||
                  "$alias_target" == */config/"$name" ]]; then
                sudo rm -f "$legacy_alias"
                sudo ln -sfn "$name" "$template_alias"
            else
                echo "WARNING: preserving unexpected legacy template symlink: $legacy_alias -> $alias_target" >&2
            fi
        elif [[ -f "$legacy_alias" && -f "$target" ]] && sudo cmp -s "$legacy_alias" "$target"; then
            sudo rm -f "$legacy_alias"
            sudo ln -sfn "$name" "$template_alias"
        fi
    done
    shopt -u nullglob
}

install_sha3x_template() {
    local target="$TEMPLATE_DIR/sha3x.conf"
    local yiimp_conf="$STORAGE_ROOT/yiimp/.yiimp.conf"
    local db_host="localhost"
    local rendered=""

    #
    # SQSYIIMP owns this algorithm template.
    # No Stratum source or binary capability detection is performed.
    #
    if [[ -f "$target" ]]; then
        echo "SHA3X algorithm template already exists; preserving: $target"
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
        echo "WARNING: SHA3X template was not installed because SQSYIIMP credentials are incomplete in $yiimp_conf" >&2
        return 0
    fi

    if [[ -n "${DBInternalIP:-}" ]]; then
        db_host="$DBInternalIP"
    fi

    rendered="$(mktemp)"

    STRATUM_URL="$StratumURL" \
    STRATUM_PASSWORD="$BlocknotifyPassword" \
    SQL_HOST="$db_host" \
    SQL_DATABASE="$YiiMPDBName" \
    SQL_USERNAME="$StratumDBUser" \
    SQL_PASSWORD="$StratumUserDBPassword" \
    python3 - "$SHA3X_TEMPLATE_SOURCE" "$rendered" <<'PY_RENDER_SHA3X'
import os
import re
import sys
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])

text = source.read_text()

replacements = {
    ("TCP", "server"): os.environ["STRATUM_URL"],
    ("TCP", "password"): os.environ["STRATUM_PASSWORD"],
    ("SQL", "host"): os.environ["SQL_HOST"],
    ("SQL", "database"): os.environ["SQL_DATABASE"],
    ("SQL", "username"): os.environ["SQL_USERNAME"],
    ("SQL", "password"): os.environ["SQL_PASSWORD"],
}

section = None
lines = []

for line in text.splitlines():
    match = re.match(r"^\s*\[([^]]+)\]\s*$", line)

    if match:
        section = match.group(1).upper()
        lines.append(line)
        continue

    rendered = line

    for (wanted_section, key), value in replacements.items():
        if (
            section == wanted_section and
            re.match(rf"^\s*{re.escape(key)}\s*=", line, re.I)
        ):
            rendered = f"{key} = {value}"
            break

    lines.append(rendered)

target.write_text("\n".join(lines) + "\n")
PY_RENDER_SHA3X

    sudo install \
        -o "$STORAGE_USER" \
        -g "$STORAGE_GROUP" \
        -m 0640 \
        "$rendered" \
        "$target"

    rm -f "$rendered"

    echo "SHA3X algorithm template installed: $target"
}


# SQS_MANAGED_ALGORITHM_TEMPLATES_V1
#
# Install algorithm templates shipped by SQSYIIMP without overwriting
# administrator-managed runtime templates.
#
# COSA is deliberately excluded from SQSYIIMP.
install_repository_algorithm_templates() {
    local source=""
    local target=""
    local name=""
    local rendered=""
    local yiimp_conf="$STORAGE_ROOT/yiimp/.yiimp.conf"
    local db_host="localhost"

    if [[ -r "$yiimp_conf" ]]; then
        # shellcheck disable=SC1090
        source "$yiimp_conf"
    fi

    if [[ -z "${StratumURL:-}" ||
          -z "${BlocknotifyPassword:-}" ||
          -z "${YiiMPDBName:-}" ||
          -z "${StratumDBUser:-}" ||
          -z "${StratumUserDBPassword:-}" ]]; then
        echo "WARNING: managed Stratum templates were not installed because SQSYIIMP credentials are incomplete in $yiimp_conf" >&2
        return 0
    fi

    if [[ -n "${DBInternalIP:-}" ]]; then
        db_host="$DBInternalIP"
    fi

    sudo install -d \
        -o "$STORAGE_USER" \
        -g "$STORAGE_GROUP" \
        -m 0755 \
        "$TEMPLATE_DIR"

    shopt -s nullglob

    for source in "$SCRIPT_DIR"/templates/*.conf; do
        name="${source##*/}"

        case "$name" in
            cosa.conf)
                echo "Skipping deliberately excluded algorithm template: $name"
                continue
                ;;
        esac

        target="$TEMPLATE_DIR/$name"

        if [[ -e "$target" ]]; then
            echo "Algorithm template already exists; preserving: $target"
            continue
        fi

        rendered="$(mktemp)"

        STRATUM_URL="$StratumURL" \
        STRATUM_PASSWORD="$BlocknotifyPassword" \
        SQL_HOST="$db_host" \
        SQL_DATABASE="$YiiMPDBName" \
        SQL_USERNAME="$StratumDBUser" \
        SQL_PASSWORD="$StratumUserDBPassword" \
        python3 - "$source" "$rendered" <<'PY_RENDER_TEMPLATE'
from pathlib import Path
import os
import re
import sys

source = Path(sys.argv[1])
target = Path(sys.argv[2])

text = source.read_text(errors="strict")

replacements = {
    ("TCP", "server"): os.environ["STRATUM_URL"],
    ("TCP", "password"): os.environ["STRATUM_PASSWORD"],
    ("SQL", "host"): os.environ["SQL_HOST"],
    ("SQL", "database"): os.environ["SQL_DATABASE"],
    ("SQL", "username"): os.environ["SQL_USERNAME"],
    ("SQL", "password"): os.environ["SQL_PASSWORD"],
}

section = None
out = []

for line in text.splitlines():
    match = re.match(
        r"^\s*\[([^]]+)\]\s*$",
        line
    )

    if match:
        section = match.group(1).upper()
        out.append(line)
        continue

    rendered = line

    for (wanted_section, key), value in replacements.items():
        if (
            section == wanted_section
            and re.match(
                rf"^\s*{re.escape(key)}\s*=",
                line,
                re.I,
            )
        ):
            rendered = f"{key} = {value}"
            break

    out.append(rendered)

target.write_text("\n".join(out) + "\n")
PY_RENDER_TEMPLATE

        sudo install \
            -o "$STORAGE_USER" \
            -g "$STORAGE_GROUP" \
            -m 0640 \
            "$rendered" \
            "$target"

        rm -f "$rendered"
        rendered=""

        echo "Algorithm template installed: $target"
    done

    shopt -u nullglob
}

sudo install -d \
    -o "$STORAGE_USER" \
    -g "$STORAGE_GROUP" \
    -m 0755 \
    "$CONFIG_DIR" \
    "$TEMPLATE_DIR"

migrate_legacy_algorithm_templates
install_sha3x_template
install_repository_algorithm_templates
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
