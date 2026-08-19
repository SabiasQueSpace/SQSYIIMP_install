#!/usr/bin/env bash

##################################################################################
# This is the entry point for configuring the system.
# Source https://mailinabox.email/ https://github.com/mail-in-a-box/mailinabox
# SQSYIIMP - SabiasQue.Space
##################################################################################

clear
source /etc/functions.sh
source /etc/yiimpool.conf

# Guard: .yiimp.conf is created later in the install — only source if it exists
if [ -f "$STORAGE_ROOT/yiimp/.yiimp.conf" ]; then
    source "$STORAGE_ROOT/yiimp/.yiimp.conf"
fi

set -eu -o pipefail

function print_error {
    read line file <<<$(caller)
    echo "An error occurred in line $line of file $file:" >&2
    sed "${line}q;d" "$file" >&2
}
trap print_error ERR

term_art
print_header "System Configuration"
print_info "Starting system configuration..."

# Set timezone to UTC
print_header "Setting TimeZone"
if [ "$(cat /etc/timezone 2>/dev/null)" != "UTC" ]; then
    print_status "Setting timezone to UTC"
    sudo timedatectl set-timezone UTC
    restart_service rsyslog
fi
print_success "Timezone set to UTC"

print_status "Installing common packages"
hide_output sudo apt-get update
apt_install_required software-properties-common build-essential gnupg2 ca-certificates curl
if is_ubuntu_noble; then
    enable_ubuntu_universe
fi
print_success "Common packages installed"

# CertBot
print_header "Installing CertBot"
if [[ "$DISTRO" == "22" || "$DISTRO" == "24" ]]; then
    print_status "Installing CertBot via Snap for Ubuntu $DISTRO"
    hide_output sudo apt install -y snapd
    hide_output sudo snap install core
    hide_output sudo snap refresh core
    hide_output sudo snap install --classic certbot
    # Only create symlink if it doesn't already exist
    if [ ! -e /usr/bin/certbot ]; then
        sudo ln -s /snap/bin/certbot /usr/bin/certbot
    fi
    print_success "CertBot installation complete"
elif [[ "$DISTRO" == "11" || "$DISTRO" == "12" || "$DISTRO" == "13" ]]; then
    print_status "Installing CertBot for Debian $DISTRO"
    hide_output sudo apt install -y certbot
    print_success "CertBot installation complete"
fi

print_header "Installing MariaDB"

# Create directory for keys if it doesn't exist
if [ ! -d /etc/apt/keyrings ]; then
    sudo mkdir -p /etc/apt/keyrings
fi

# Download and add the MariaDB signing key
if [ ! -f /etc/apt/keyrings/mariadb.gpg ]; then
    print_status "Downloading MariaDB signing key"
    sudo curl -fsSL https://mariadb.org/mariadb_release_signing_key.pgp | sudo gpg --dearmor -o /etc/apt/keyrings/mariadb.gpg
fi

REPO_LINE=""
case "$DISTRO" in
    "22")  # Ubuntu 22.04
        REPO_LINE="deb [signed-by=/etc/apt/keyrings/mariadb.gpg arch=amd64,arm64,ppc64el,s390x] https://mirror.mariadb.org/repo/11.8/ubuntu jammy main"
        ;;
    "24")  # Ubuntu 24.04
        REPO_LINE="deb [signed-by=/etc/apt/keyrings/mariadb.gpg arch=amd64,arm64,ppc64el,s390x] https://mirror.mariadb.org/repo/11.8/ubuntu noble main"
        ;;
    "13")  # Debian 13
        REPO_LINE="deb [signed-by=/etc/apt/keyrings/mariadb.gpg arch=amd64,arm64,i386,ppc64el] https://mirror.mariadb.org/repo/11.8/debian trixie main"
        ;;
    "12")  # Debian 12
        REPO_LINE="deb [signed-by=/etc/apt/keyrings/mariadb.gpg arch=amd64,arm64,i386,ppc64el] https://mirror.mariadb.org/repo/11.8/debian bookworm main"
        ;;
    "11")  # Debian 11
        REPO_LINE="deb [signed-by=/etc/apt/keyrings/mariadb.gpg arch=amd64,arm64,i386,ppc64el] https://mirror.mariadb.org/repo/11.8/debian bullseye main"
        ;;
    *)
        print_error "Unsupported Ubuntu/Debian version: $DISTRO"
        exit 1
        ;;
esac

# Write MariaDB repository to a dedicated sources list file
echo "$REPO_LINE" | sudo tee /etc/apt/sources.list.d/mariadb.list >/dev/null
print_success "MariaDB repository setup complete"


export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

#prepare_apt_for_install

# Installer hang some time from here TODO: Fix this.

print_header "Updating System"

hide_output sudo apt-get update
hide_output sudo -E apt-get upgrade -y
hide_output sudo -E apt-get dist-upgrade -y
hide_output sudo -E apt-get autoremove -y

print_success "System updated"

# prepare_apt_for_install

print_header "Installing Base System Packages"

apt_install_required python3 python3-dev python3-pip coreutils bc unzip \
    unattended-upgrades cron ntpdate fail2ban screen rsyslog nginx haproxy supervisor
apt_install_optional haveged pollinate
# ntp (classic) conflicts with systemd-timesyncd on Ubuntu 24.04+; ntpdate is
# retained only for one-shot compatibility where an older helper still calls it.

print_success "Base system packages installed"

print_header "Initializing System Random Number Generator"
# Modern kernels seed the CRNG themselves. If pollinate is available, use it as
# an additional cloud entropy source without making it a hard dependency.
if command -v pollinate >/dev/null 2>&1; then
    hide_output sudo pollinate -q -r
fi
print_success "Random number generator initialized"

print_header "Initializing UFW Firewall"
set +eu +o pipefail
if [ -z "${DISABLE_FIREWALL:-}" ]; then
    hide_output sudo apt-get install -y ufw

    print_status "Configuring firewall rules..."
    ufw_allow ssh
    print_success "SSH port opened"

    ufw_allow http
    print_success "HTTP port opened"

    ufw_allow https
    print_success "HTTPS port opened"

    SSH_PORT=$(sshd -T 2>/dev/null | grep "^port " | sed "s/port //")
    if [ -n "$SSH_PORT" ] && [ "$SSH_PORT" != "22" ]; then
        print_status "Opening alternate SSH port: $SSH_PORT"
        ufw_allow "$SSH_PORT"
        print_success "Alternate SSH port opened"
    fi

    hide_output sudo ufw --force enable
    print_success "Firewall enabled and configured"
fi
set -eu -o pipefail

print_header "Installing YiiMP Required Packages"
if [ -f /usr/sbin/apache2 ]; then
    print_status "Removing Apache..."
    hide_output sudo apt-get -y purge apache2 apache2-*
    hide_output sudo apt-get -y --purge autoremove
    print_success "Apache removed"
fi

print_header "Installing PHP 8.1"

# Ubuntu 24.04.x (Noble), including 24.04.4, uses the Ubuntu-specific
# Ondrej PHP PPA. Debian uses packages.sury.org. The helper validates that
# php8.1-fpm is visible before any PHP package installation begins.
install_php81_stack
print_success "PHP 8.1 packages installed"

print_header "Installing YiiMP System Libraries"
# Prefer package names that are stable on Ubuntu 24.04. The t64 runtime
# transitions are pulled in by their -dev packages and are not hardcoded.
apt_install_required \
    fail2ban ntpdate python3 python3-dev python3-pip coreutils unzip \
    unattended-upgrades cron pwgen imagemagick memcached \
    libgmp-dev default-libmysqlclient-dev libcurl4-openssl-dev \
    libkrb5-dev libldap-dev libgnutls28-dev \
    build-essential libtool autotools-dev automake pkg-config libevent-dev \
    bsdextrautils libssl-dev cmake ca-certificates lsb-release nginx \
    libsodium-dev libnghttp2-dev libssh2-1-dev libpsl-dev \
    libssh-dev libbrotli-dev

apt_install_optional librtmp-dev libidn-dev libcanberra-gtk-module pollinate
print_success "YiiMP system libraries installed"

print_header "Installing phpMyAdmin"
_pma_dir=$(mktemp -d)
print_status "Downloading phpMyAdmin..."
hide_output sudo wget -q -P "$_pma_dir" https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.tar.gz
print_status "Extracting phpMyAdmin..."
hide_output sudo tar xzf "$_pma_dir/phpMyAdmin-latest-all-languages.tar.gz" -C "$_pma_dir"
sudo rm "$_pma_dir/phpMyAdmin-latest-all-languages.tar.gz"
# Remove existing installation so mv replaces rather than nests inside it
if [ -d /usr/share/phpmyadmin ]; then
    sudo rm -rf /usr/share/phpmyadmin
fi
sudo mv "$_pma_dir"/phpMyAdmin-*-all-languages /usr/share/phpmyadmin
sudo rm -rf "$_pma_dir"
sudo mkdir -p /usr/share/phpmyadmin/tmp
sudo chown -R www-data:www-data /usr/share/phpmyadmin/tmp
sudo chmod 755 /usr/share/phpmyadmin/tmp
print_success "phpMyAdmin installation complete"

print_header "Setting PHP Version"
# Register php8.1 first if not already registered, then set as default
if ! update-alternatives --list php 2>/dev/null | grep -q "/usr/bin/php8.1"; then
    sudo update-alternatives --install /usr/bin/php php /usr/bin/php8.1 81
fi
sudo update-alternatives --set php /usr/bin/php8.1
print_success "PHP version set to 8.1"

print_header "Cloning YiiMP Repository"

hide_output sudo git clone "${YiiMPRepo}" "$STORAGE_ROOT/yiimp/yiimp_setup/yiimp"

print_success "YiiMP repository cloned successfully"

print_header "starting services"

hide_output sudo systemctl start nginx
hide_output sudo systemctl start php8.1-fpm

print_success "services started"
# restart_service nginx

set +eu +o pipefail
cd "$HOME/sqsyiimp/yiimp_single"
