#!/usr/bin/env bash

#####################################################
# SQSYIIMP - SabiasQue.Space
#
# This script contains utility functions for the upgrade process
#
# Author: SabiasQue.Space
# Date: 2026-03-06
#####################################################

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
NC='\033[0m'

# SQSYIIMP storage/service configuration.
if [[ -r /etc/yiimpool.conf ]]; then
    # shellcheck disable=SC1091
    source /etc/yiimpool.conf
fi

STORAGE_USER="${STORAGE_USER:-crypto-data}"
STORAGE_GROUP="${STORAGE_GROUP:-${STORAGE_USER}}"
STORAGE_ROOT="${STORAGE_ROOT:-/home/${STORAGE_USER}}"

STRATUM_DIR="${STORAGE_ROOT}/yiimp/site/stratum"
STRATUM_CONF="${STRATUM_DIR}/config"
SITE_DIR="${STORAGE_ROOT}/yiimp/site"
BACKUP_DIR="$HOME/yiimpool_backups"

# Query the public SQSYIIMP Git repository and return the latest tag.
# stdout is reserved exclusively for the resulting tag.
get_latest_release() {
    local repo="https://github.com/SabiasQueSpace/SQSYIIMP_install.git"
    local latest=""

    if ! command -v git >/dev/null 2>&1; then
        echo "Git is not installed; cannot check SQSYIIMP updates." >&2
        return 1
    fi

    latest="$(
        git ls-remote \
            --tags \
            --refs \
            "$repo" \
            'v*' 2>/dev/null |
        awk -F/ '{print $3}' |
        sort -V |
        tail -n 1
    )"

    if [[ -z "$latest" ]]; then
        echo "Could not retrieve SQSYIIMP tags from GitHub." >&2
        return 1
    fi

    printf '%s\n' "$latest"
}

log_message() {
    local level=$1
    local message=$2
    echo -e "${level}[$(date '+%Y-%m-%d %H:%M:%S')] ${message}${NC}"
}

check_services() {
    local services=("nginx")
    local all_running=true

    if systemctl list-unit-files mariadb.service >/dev/null 2>&1; then
        services+=("mariadb")
    elif systemctl list-unit-files mysql.service >/dev/null 2>&1; then
        services+=("mysql")
    else
        log_message "$RED" "Neither mariadb.service nor mysql.service is installed"
        all_running=false
    fi

    if systemctl list-unit-files php8.1-fpm.service >/dev/null 2>&1; then
        services+=("php8.1-fpm")
    else
        log_message "$RED" "php8.1-fpm.service is not installed"
        all_running=false
    fi

    local service
    for service in "${services[@]}"; do
        if ! systemctl is-active --quiet "$service"; then
            log_message "$RED" "Service $service is not running"
            all_running=false
        fi
    done

    if [ "$all_running" = true ]; then
        log_message "$GREEN" "All required services are running"
        return 0
    fi
    return 1
}

verify_requirements() {
    log_message "$YELLOW" "Verifying system requirements..."

    local free_space=$(df -m / | awk 'NR==2 {print $4}')
    if [ "$free_space" -lt 5000 ]; then
        log_message "$RED" "Not enough disk space. At least 5GB required."
        return 1
    fi

    # Use Linux "available" memory instead of only completely free RAM.
    # A normal SQSYIIMP installer update is lightweight; rebuilding Stratum
    # requires considerably more working memory.
    local available_mem
    local required_mem=256

    available_mem=$(free -m | awk '/^Mem:/ {print $7}')

    if [[ "${UPGRADE_TYPE:-full}" == "stratum" ]]; then
        required_mem=1024
    fi

    if [[ -z "$available_mem" || ! "$available_mem" =~ ^[0-9]+$ ]]; then
        log_message "$RED" "Could not determine available system memory."
        return 1
    fi

    log_message "$YELLOW" "Available memory: ${available_mem} MB (required: ${required_mem} MB)"

    if [ "$available_mem" -lt "$required_mem" ]; then
        log_message "$RED" "Not enough available memory. ${required_mem} MB required."
        return 1
    fi

    if ! check_services; then
        return 1
    fi

    log_message "$GREEN" "System requirements verified"
    return 0
}

backup_system() {
    log_message "$YELLOW" "Creating system backup..."

    local backup_name="yiimpool_backup_$(date +%Y%m%d_%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"

    sudo mkdir -p "$backup_path"
    sudo cp -r /etc/yiimpool* "$backup_path/"

    if [ -d "$SITE_DIR" ]; then
        sudo cp -r "$SITE_DIR/configuration" "$backup_path/site_config"
        sudo cp -r "$SITE_DIR/stratum/config" "$backup_path/stratum_config"
    fi

    if command -v mysqldump &>/dev/null; then
        if [ -f "/root/.my.cnf" ]; then
            sudo mysqldump --defaults-file=/root/.my.cnf --all-databases > "$backup_path/database_backup.sql"
        fi
    fi

    cd "$BACKUP_DIR"
    sudo tar -czf "${backup_name}.tar.gz" "$backup_name"
    sudo rm -rf "$backup_name"

    log_message "$GREEN" "Backup completed: ${backup_name}.tar.gz"
}

upgrade_stratum() {
    log_message "$YELLOW" "Upgrading stratum..."

    if [ -f "$STORAGE_ROOT/yiimp/.yiimp.conf" ]; then
        source $STORAGE_ROOT/yiimp/.yiimp.conf
    else
        log_message "$RED" "YiiMP configuration file not found. Exiting..."
        return 1
    fi

    if [ -z "$YiiMPRepo" ]; then
        log_message "$RED" "YiiMP repository URL not found in configuration. Exiting..."
        return 1
    fi

    YIIMP_DIR="$STORAGE_ROOT/yiimp/yiimp_setup/yiimp"

    if [ -d "$STRATUM_CONF" ]; then
        log_message "$GREEN" "Backing up stratum configuration..."
        BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        sudo cp -r "$STRATUM_CONF" "${STRATUM_CONF}_backup_${BACKUP_TIMESTAMP}"

        if [ -f "$STRATUM_CONF/stratum.conf" ]; then
            sudo cp "$STRATUM_CONF/stratum.conf" "${STRATUM_CONF}/stratum.conf.backup_${BACKUP_TIMESTAMP}"
        fi
    else
        log_message "$RED" "Stratum configuration directory not found at $STRATUM_CONF"
        return 1
    fi

    if [[ -d "$YIIMP_DIR" ]]; then
        sudo rm -rf "$YIIMP_DIR"
    fi

    log_message "$GREEN" "Cloning fresh YiiMP repository from $YiiMPRepo..."
    if ! sudo git clone "${YiiMPRepo}" "$YIIMP_DIR"; then
        log_message "$RED" "Failed to clone YiiMP repository. Exiting..."
        return 1
    fi

    log_message "$GREEN" "Selecting a compatible stratum compiler..."
    select_stratum_compiler || return 1
    log_message "$GREEN" "Using $STRATUM_CC / $STRATUM_CXX"

    cd $YIIMP_DIR/stratum || {
        log_message "$RED" "Failed to change to stratum directory. Exiting..."
        return 1
    }

    sudo git submodule init
    sudo git submodule update

    log_message "$GREEN" "Building stratum components..."

    if ! sudo env CC="$STRATUM_CC" CXX="$STRATUM_CXX" make -C algos; then
        log_message "$RED" "Failed to build algos. Please check the build output above for errors."
        return 1
    fi
    log_message "$GREEN" "algos built successfully!"

    if ! sudo env CC="$STRATUM_CC" CXX="$STRATUM_CXX" make -C sha3; then
        log_message "$RED" "Failed to build sha3. Please check the build output above for errors."
        return 1
    fi
    log_message "$GREEN" "sha3 built successfully!"

    if ! sudo env CC="$STRATUM_CC" CXX="$STRATUM_CXX" make -C iniparser; then
        log_message "$RED" "Failed to build iniparser. Please check the build output above for errors."
        return 1
    fi
    log_message "$GREEN" "iniparser built successfully!"

    cd secp256k1 || {
        log_message "$RED" "Failed to change to secp256k1 directory. Exiting..."
        return 1
    }

    sudo chmod +x autogen.sh
    hide_output sudo ./autogen.sh
    hide_output sudo env CC="$STRATUM_CC" CXX="$STRATUM_CXX" ./configure --enable-experimental --enable-module-ecdh --with-bignum=no --enable-endomorphism
    hide_output sudo env CC="$STRATUM_CC" CXX="$STRATUM_CXX" make

    cd $YIIMP_DIR/stratum || {
        log_message "$RED" "Failed to return to stratum directory. Exiting..."
        return 1
    }

    if ! sudo env CC="$STRATUM_CC" CXX="$STRATUM_CXX" make buildonly; then
        log_message "$RED" "Failed to build stratum. Please check the build output above for errors."
        return 1
    fi
    log_message "$GREEN" "stratum built successfully!"

    log_message "$GREEN" "Installing stratum..."
    if ! sudo mv stratum "$STRATUM_DIR/"; then
        log_message "$RED" "Failed to install stratum."
        return 1
    fi

    sudo chown "$STORAGE_USER:$STORAGE_GROUP" "$STRATUM_DIR/stratum"
    sudo chmod 750 "$STRATUM_DIR/stratum"

    sudo mkdir -p "$STRATUM_CONF"

    log_message "$GREEN" "Restoring stratum configuration..."
    LATEST_BACKUP=$(ls -td "${STRATUM_CONF}_backup_"* | head -1)
    if [ -d "$LATEST_BACKUP" ]; then
        sudo cp -r "$LATEST_BACKUP/"* "$STRATUM_CONF/"
        sudo chown -R "$STORAGE_USER:$STORAGE_GROUP" "$STRATUM_CONF"
        sudo chmod -R 750 "$STRATUM_CONF"
        log_message "$GREEN" "Stratum configuration restored from $LATEST_BACKUP"
    else
        log_message "$YELLOW" "No backup found — applying credentials to fresh config.sample files..."
    fi

    log_message "$YELLOW" "Applying pool credentials to stratum config files..."
    UPDATE_CONF_SCRIPT="$HOME/sqsyiimp/yiimp_upgrade/utils/update_stratum_conf.sh"
    if [ -f "$UPDATE_CONF_SCRIPT" ]; then
        if ! bash "$UPDATE_CONF_SCRIPT"; then
            log_message "$RED" "Failed to update stratum config credentials."
            return 1
        fi
    else
        log_message "$RED" "update_stratum_conf.sh not found at $UPDATE_CONF_SCRIPT"
        return 1
    fi

    log_message "$GREEN" "Installing Stratum management tools..."
    if ! bash "$HOME/sqsyiimp/stratum_manager/install.sh"; then
        log_message "$RED" "Failed to install Stratum management tools."
        return 1
    fi

    cd $YIIMP_DIR/web/yaamp/core/functions/
    sudo cp -r yaamp.php $SITE_DIR/web/yaamp/core/functions

    log_message "$GREEN" "Stratum upgrade completed successfully!"
    return 0
}

sync_installer_runtime() {
    local repo="$HOME/sqsyiimp"
    local daemonbuilder_source="$repo/daemon_builder/utils"
    local daemonbuilder_target="$STORAGE_ROOT/daemon_builder"

    log_message "$YELLOW" "Synchronizing SQSYIIMP runtime files..."

    if [[ ! -f "$repo/install/functions.sh" ]]; then
        log_message "$RED" "Missing $repo/install/functions.sh"
        return 1
    fi

    if [[ ! -d "$daemonbuilder_source" ]]; then
        log_message "$RED" "Missing DaemonBuilder source: $daemonbuilder_source"
        return 1
    fi

    # Active SQSYIIMP functions.
    if ! sudo install \
        -o root \
        -g root \
        -m 644 \
        "$repo/install/functions.sh" \
        /etc/functions.sh
    then
        log_message "$RED" "Failed to update /etc/functions.sh"
        return 1
    fi

    # Active MOTD runtime. Installing these files is required during upgrades;
    # updating the repository alone does not change /etc/update-motd.d/.
    local distro_id=""
    local motd_source=""
    local motd_file=""

    if [[ -r /etc/os-release ]]; then
        distro_id=$(awk -F= '$1 == "ID" {gsub(/"/, "", $2); print $2}' /etc/os-release)
    fi

    case "$distro_id" in
        ubuntu)
            motd_source="$repo/yiimp_single/ubuntu/etc/update-motd.d"
            ;;
        debian)
            motd_source="$repo/yiimp_single/debian/etc/update-motd.d"
            ;;
        *)
            log_message "$RED" "Unsupported distribution for MOTD synchronization: ${distro_id:-unknown}"
            return 1
            ;;
    esac

    for motd_file in 00-header 10-sysinfo 90-footer; do
        if [[ ! -f "$motd_source/$motd_file" ]]; then
            log_message "$RED" "Missing MOTD source file: $motd_source/$motd_file"
            return 1
        fi

        if ! bash -n "$motd_source/$motd_file"; then
            log_message "$RED" "Invalid MOTD syntax: $motd_source/$motd_file"
            return 1
        fi
    done

    if ! sudo install -d -o root -g root -m 755 /etc/update-motd.d; then
        log_message "$RED" "Failed to prepare /etc/update-motd.d"
        return 1
    fi

    for motd_file in 00-header 10-sysinfo 90-footer; do
        if ! sudo install \
            -o root \
            -g root \
            -m 755 \
            "$motd_source/$motd_file" \
            "/etc/update-motd.d/$motd_file"
        then
            log_message "$RED" "Failed to update /etc/update-motd.d/$motd_file"
            return 1
        fi
    done

    log_message "$GREEN" "SQSYIIMP MOTD runtime synchronized successfully"

    # Active DaemonBuilder runtime.
    if ! sudo mkdir -p "$daemonbuilder_target"; then
        log_message "$RED" "Failed to create $daemonbuilder_target"
        return 1
    fi

    if ! sudo cp -r "$daemonbuilder_source"/. "$daemonbuilder_target"/; then
        log_message "$RED" "Failed to synchronize DaemonBuilder runtime"
        return 1
    fi

    if id "$STORAGE_USER" >/dev/null 2>&1; then
        sudo chown -R "$STORAGE_USER:$STORAGE_GROUP" "$daemonbuilder_target"
    fi

    # Canonical command wrapper.
    cat <<'EOF' | sudo tee /usr/bin/daemonbuilder >/dev/null
#!/usr/bin/env bash

source /etc/functions.sh
source /etc/yiimpool.conf

cd "$STORAGE_ROOT/daemon_builder" || exit 1
exec bash start.sh
EOF

    sudo chmod 755 /usr/bin/daemonbuilder || return 1

    # Validate the critical runtime scripts after installation.
    local runtime_file
    for runtime_file in start.sh source.sh upgrade.sh menu.sh; do
        if [[ ! -f "$daemonbuilder_target/$runtime_file" ]]; then
            log_message "$RED" "Missing runtime file: $daemonbuilder_target/$runtime_file"
            return 1
        fi

        if ! bash -n "$daemonbuilder_target/$runtime_file"; then
            log_message "$RED" "Invalid syntax: $daemonbuilder_target/$runtime_file"
            return 1
        fi
    done

    log_message "$GREEN" "SQSYIIMP runtime files synchronized successfully"
    return 0
}

verify_upgrade() {
    log_message "$YELLOW" "Verifying upgrade..."

    if ! check_services; then
        log_message "$RED" "Service check failed after upgrade"
        return 1
    fi

    log_message "$GREEN" "Upgrade verification completed successfully"
    return 0
}

restore_from_backup() {
    local backup_file=$1

    if [ ! -f "$backup_file" ]; then
        log_message "$RED" "Backup file not found: $backup_file"
        return 1
    fi

    log_message "$YELLOW" "Restoring from backup: $backup_file"

    sudo systemctl stop nginx php8.1-fpm
    if systemctl list-unit-files mariadb.service >/dev/null 2>&1; then sudo systemctl stop mariadb; elif systemctl list-unit-files mysql.service >/dev/null 2>&1; then sudo systemctl stop mysql; fi

    cd "$BACKUP_DIR"
    sudo tar -xzf "$backup_file"

    local backup_dir="${backup_file%.tar.gz}"

    sudo cp -r "$backup_dir/yiimpool"* /etc/

    if [ -d "$backup_dir/site_config" ]; then
        sudo cp -r "$backup_dir/site_config"/* "$SITE_DIR/configuration/"
    fi

    if [ -d "$backup_dir/stratum_config" ]; then
        sudo cp -r "$backup_dir/stratum_config"/* "$SITE_DIR/stratum/config/"
    fi

    sudo rm -rf "$backup_dir"

    if systemctl list-unit-files mariadb.service >/dev/null 2>&1; then sudo systemctl start mariadb; elif systemctl list-unit-files mysql.service >/dev/null 2>&1; then sudo systemctl start mysql; fi
    sudo systemctl start nginx php8.1-fpm

    log_message "$GREEN" "Restore completed"
    return 0
}
