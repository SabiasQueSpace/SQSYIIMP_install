#!/usr/bin/env bash

##################################################################################
# This is the entry point for configuring the system.
# Source https://mailinabox.email/ https://github.com/mail-in-a-box/mailinabox
# SQSYIIMP - SabiasQue.Space
##################################################################################

export TERM=xterm

source /etc/functions.sh
source /etc/yiimpool.conf

if [[ ! -e "$STORAGE_ROOT/yiimp/" ]]; then
    sudo mkdir -p "$STORAGE_ROOT/yiimp/"
fi
sudo cp -r /tmp/.yiimp.conf "$STORAGE_ROOT/yiimp/"
source "$STORAGE_ROOT/yiimp/.yiimp.conf"

# source $HOME/sqsyiimp/yiimp_single/.wireguard.install.cnf

set -eu -o pipefail

function print_error {
    read -r line file <<< "$(caller)"
    echo "An error occurred in line $line of file $file:" >&2
    sed "${line}q;d" "$file" >&2
}
trap print_error ERR

term_art
print_header "Remote Stratum System Configuration"
detect_os_compat
if is_ubuntu_noble; then
    enable_ubuntu_universe
fi

# Set timezone to UTC
print_status "Setting timezone to UTC..."
if [ ! -f /etc/timezone ]; then
    sudo bash -c 'echo "Etc/UTC" > /etc/timezone'
    restart_service rsyslog
fi

hide_output sudo apt-get install -y software-properties-common build-essential

# CertBot

if [[ "$DISTRO" == "22" || "$DISTRO" == "24" ]]; then
    print_status "Installing CertBot (snap)..."
    hide_output sudo apt install -y snapd
    hide_output sudo snap install core
    hide_output sudo snap refresh core
    hide_output sudo snap install --classic certbot
    if [ ! -e /usr/bin/certbot ]; then
        sudo ln -s /snap/bin/certbot /usr/bin/certbot
    fi
    print_success "CertBot installed."

elif [[ "$DISTRO" == "12" || "$DISTRO" == "11" || "$DISTRO" == "13" ]]; then
    print_status "Installing CertBot..."
    hide_output sudo apt install -y certbot
    print_success "CertBot installed."
fi

print_status "Installing MariaDB..."

if [ ! -d /etc/apt/keyrings ]; then
    sudo mkdir -p /etc/apt/keyrings
fi

if [ ! -f /etc/apt/keyrings/mariadb.gpg ]; then
    print_status "Downloading MariaDB signing key..."
    sudo curl -fsSL https://mariadb.org/mariadb_release_signing_key.pgp | sudo gpg --dearmor -o /etc/apt/keyrings/mariadb.gpg
fi

REPO_LINE=""
case "$DISTRO" in
    "22")   # Ubuntu 22.04
        REPO_LINE="deb [signed-by=/etc/apt/keyrings/mariadb.gpg arch=amd64,arm64,ppc64el,s390x] https://mirror.mariadb.org/repo/11.8/ubuntu jammy main"
        ;;
    "24")   # Ubuntu 24.04
        REPO_LINE="deb [signed-by=/etc/apt/keyrings/mariadb.gpg arch=amd64,arm64,ppc64el,s390x] https://mirror.mariadb.org/repo/11.8/ubuntu noble main"
        ;;
    "13")   # Debian 13
        REPO_LINE="deb [signed-by=/etc/apt/keyrings/mariadb.gpg arch=amd64,arm64,i386,ppc64el] https://mirror.mariadb.org/repo/11.8/debian trixie main"
        ;;
    "12")   # Debian 12
        REPO_LINE="deb [signed-by=/etc/apt/keyrings/mariadb.gpg arch=amd64,arm64,i386,ppc64el] https://mirror.mariadb.org/repo/11.8/debian bookworm main"
        ;;
    "11")   # Debian 11
        REPO_LINE="deb [signed-by=/etc/apt/keyrings/mariadb.gpg arch=amd64,arm64,i386,ppc64el] https://mirror.mariadb.org/repo/11.8/debian bullseye main"
        ;;
    *)
        echo "Unsupported distro version: $DISTRO"
        exit 1
        ;;
esac

echo "$REPO_LINE" | sudo tee /etc/apt/sources.list.d/mariadb.list >/dev/null
print_success "MariaDB repository configured."
hide_output sudo apt-get update
prepare_apt_for_install

if [ ! -f /boot/grub/menu.lst ]; then
    apt_get_quiet upgrade
else
    sudo rm /boot/grub/menu.lst
    sudo update-grub-legacy-ec2 -y
    apt_get_quiet upgrade
fi

apt_get_quiet dist-upgrade
apt_get_quiet autoremove

prepare_apt_for_install

print_status "Installing base system packages..."
apt_install_required python3 python3-dev python3-pip wget curl git sudo coreutils bc \
    unzip unattended-upgrades cron ntpdate fail2ban screen rsyslog nginx
apt_install_optional haveged pollinate lolcat
print_success "Base system packages installed."

print_status "Initializing system random number generator..."
if command -v pollinate >/dev/null 2>&1; then
    hide_output sudo pollinate -q -r
fi
print_success "Random number generator initialized."

print_status "Initializing UFW Firewall..."
set +eu +o pipefail
if [ -z "${DISABLE_FIREWALL:-}" ]; then
    hide_output sudo apt-get install -y ufw
    print_status "Allowing incoming connections to SSH, HTTP, and HTTPS..."
    ufw_allow ssh
    sleep 0.5
    print_success "SSH port: OPEN"
    sleep 0.5
    ufw_allow http
    print_success "HTTP port: OPEN"
    sleep 0.5
    ufw_allow https
    print_success "HTTPS port: OPEN"

    SSH_PORT=$(sshd -T 2>/dev/null | grep "^port " | sed "s/port //")
    if [ ! -z "$SSH_PORT" ] && [ "$SSH_PORT" != "22" ]; then
        print_status "Opening alternate SSH port: $SSH_PORT"
        ufw_allow $SSH_PORT
        sleep 0.5
        print_success "Alternate SSH port $SSH_PORT: OPEN"
        ufw_allow http
        sleep 0.5
        ufw_allow https
        sleep 0.5
    fi

    hide_output sudo ufw --force enable
    print_success "UFW Firewall enabled."
fi
set -eu -o pipefail

print_status "Installing YiiMP required system packages..."
if [ -f /usr/sbin/apache2 ]; then
    print_status "Removing Apache..."
    hide_output sudo apt-get -y purge apache2 apache2-*
    hide_output sudo apt-get -y --purge autoremove
fi

hide_output sudo apt-get update

print_status "Installing PHP 8.1..."
install_php81_stack

print_status "Installing remote YiiMP system libraries..."
apt_install_required \
    pwgen libgmp-dev default-libmysqlclient-dev libcurl4-openssl-dev \
    libkrb5-dev libldap-dev libgnutls28-dev build-essential libtool \
    autotools-dev automake pkg-config libevent-dev bsdextrautils libssl-dev \
    cmake gnupg2 ca-certificates lsb-release nginx libsodium-dev \
    libnghttp2-dev libssh2-1-dev libpsl-dev libssh-dev libbrotli-dev \
    imagemagick memcached
apt_install_optional librtmp-dev libidn-dev libcanberra-gtk-module
print_success "Remote YiiMP system libraries installed."

print_status "Setting PHP 8.1 as the system default..."
if ! update-alternatives --list php 2>/dev/null | grep -q "/usr/bin/php8.1"; then
    sudo update-alternatives --install /usr/bin/php php /usr/bin/php8.1 81
fi
sudo update-alternatives --set php /usr/bin/php8.1
print_success "PHP 8.1 set as default."

print_status "Cloning YiiMP repository..."
hide_output sudo git clone "${YiiMPRepo}" "$STORAGE_ROOT/yiimp/yiimp_setup/yiimp"
print_success "YiiMP repository cloned."

print_status "Restarting nginx..."
hide_output sudo service nginx restart
sleep 0.5

print_success "Remote stratum system configuration complete."

set +eu +o pipefail
exit 0
