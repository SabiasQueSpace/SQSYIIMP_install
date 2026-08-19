#!/usr/bin/env bash

##########################################
# SQSYIIMP - SabiasQue.Space
#
# Applies pool credentials and pool identity to every *.conf
# file inside the live stratum/config
# directory.  Keeps the same credential substitutions as yiimp_single/stratum.sh
# and synchronizes coinbaseextra from YAAMP_SITE_NAME
# so both the initial install and the
# upgrade path stay in sync.
#
# Sources required:
#   /etc/functions.sh
#   /etc/yiimpool.conf
#   $STORAGE_ROOT/yiimp/.yiimp.conf
#   $HOME/sqsyiimp/yiimp_single/.wireguard.install.cnf
#
# Author: SabiasQue.Space
# Date: 2026-03-14
##########################################

source /etc/functions.sh
source /etc/yiimpool.conf
source "$STORAGE_ROOT/yiimp/.yiimp.conf"
source "$HOME/sqsyiimp/yiimp_single/.wireguard.install.cnf"

# Refresh the coinbase helper functions from the repository when an existing
# installation still has an older /etc/functions.sh.
if ! declare -F get_pool_coinbase_tag >/dev/null 2>&1 || \
   ! declare -F apply_coinbaseextra_to_configs >/dev/null 2>&1; then
    if [ -r "$HOME/sqsyiimp/install/functions.sh" ]; then
        source "$HOME/sqsyiimp/install/functions.sh"
    fi
fi

if ! declare -F get_pool_coinbase_tag >/dev/null 2>&1 || \
   ! declare -F apply_coinbaseextra_to_configs >/dev/null 2>&1; then
    echo "ERROR: SQSYIIMP coinbase helper functions are unavailable." >&2
    exit 1
fi

# log_message is defined in the upgrade utils/functions.sh but this script may
# run in its own subshell (via `bash`), so define it here to be self-contained.
log_message() {
    local level=$1
    local message=$2
    echo -e "${level}[$(date '+%Y-%m-%d %H:%M:%S')] ${message}${NC}"
}

STRATUM_CONF="$STORAGE_ROOT/yiimp/site/stratum/config"

# ── Guard ────────────────────────────────────────────────────────────────────
if [ ! -d "$STRATUM_CONF" ]; then
    log_message "$RED" "Stratum config directory not found: $STRATUM_CONF"
    exit 1
fi

CONF_COUNT=$(find "$STRATUM_CONF" -maxdepth 1 -name "*.conf" | wc -l)
if [ "$CONF_COUNT" -eq 0 ]; then
    log_message "$RED" "No .conf files found in $STRATUM_CONF"
    exit 1
fi

log_message "$YELLOW" "Updating $CONF_COUNT stratum config file(s) in $STRATUM_CONF ..."
cd "$STRATUM_CONF" || exit 1

# ── Blocknotify password ──────────────────────────────────────────────────────
sudo sed -i "s/password = tu8tu5/password = $BlocknotifyPassword/g" *.conf
log_message "$GREEN" "  blocknotify password applied"

# ── Pool / stratum URL ────────────────────────────────────────────────────────
sudo sed -i "s/server = yaamp.com/server = $StratumURL/g" *.conf
log_message "$GREEN" "  stratum server URL applied  ($StratumURL)"

# ── Coinbase pool identity ───────────────────────────────────────────────────
if POOL_COINBASE_TAG="$(get_pool_coinbase_tag)"; then
    if apply_coinbaseextra_to_configs "$STRATUM_CONF" "$POOL_COINBASE_TAG"; then
        log_message "$GREEN" "  coinbase pool identity applied  ($POOL_COINBASE_TAG)"
    else
        log_message "$RED" "Unable to synchronize coinbaseextra in Stratum config files"
        exit 1
    fi
else
    log_message "$RED" "Unable to resolve YAAMP_SITE_NAME for coinbaseextra"
    exit 1
fi

# ── Database host (WireGuard vs local) ───────────────────────────────────────
if [[ "$wireguard" == "true" ]]; then
    sudo sed -i "s/host = yaampdb/host = $DBInternalIP/g" *.conf
    log_message "$GREEN" "  DB host set to WireGuard internal IP ($DBInternalIP)"
else
    sudo sed -i "s/host = yaampdb/host = localhost/g" *.conf
    log_message "$GREEN" "  DB host set to localhost"
fi

# ── Database name ─────────────────────────────────────────────────────────────
sudo sed -i "s/database = yaamp/database = $YiiMPDBName/g" *.conf
log_message "$GREEN" "  DB name applied  ($YiiMPDBName)"

# ── Database username ─────────────────────────────────────────────────────────
sudo sed -i "s/username = root/username = $StratumDBUser/g" *.conf
log_message "$GREEN" "  DB username applied  ($StratumDBUser)"

# ── Database password ─────────────────────────────────────────────────────────
sudo sed -i "s/password = patofpaq/password = $StratumUserDBPassword/g" *.conf
log_message "$GREEN" "  DB password applied"

# ── Permissions ───────────────────────────────────────────────────────────────
sudo chown -R www-data:www-data "$STRATUM_CONF"
sudo chmod -R 750 "$STRATUM_CONF"

log_message "$GREEN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_message "$GREEN" "  Stratum credentials and coinbase identity updated successfully!"
log_message "$GREEN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
