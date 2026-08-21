#!/usr/bin/env bash

##################################################################################
# This is the entry point for configuring the system.                            #
# Source https://mailinabox.email/ https://github.com/mail-in-a-box/mailinabox   #
# SQSYIIMP - SabiasQue.Space
##################################################################################

source /etc/functions.sh
cd ~/sqsyiimp/install
clear

# Get logged in user name
whoami=`whoami`
print_header "Existing user setup"
print_status "Granting sudo and yiimpool command for user $whoami"
sudo usermod -aG sudo ${whoami}

echo '# yiimp
# It needs passwordless sudo functionality.
'""''"${whoami}"''""' ALL=(ALL) NOPASSWD:ALL
' | sudo -E tee /etc/sudoers.d/${whoami} >/dev/null 2>&1

echo '
cd ~/sqsyiimp/install
bash start.sh
' | sudo -E tee /usr/bin/yiimpool >/dev/null 2>&1
sudo chmod +x /usr/bin/yiimpool

# Check required files and set global variables
cd $HOME/sqsyiimp/install
source pre_setup.sh

# Create the dedicated storage/service account and its data root.
STORAGE_GROUP="${STORAGE_GROUP:-${STORAGE_USER}}"

if ! getent group "$STORAGE_GROUP" >/dev/null 2>&1; then
    sudo groupadd "$STORAGE_GROUP"
fi

if ! id -u "$STORAGE_USER" >/dev/null 2>&1; then
    sudo useradd \
        --create-home \
        --home-dir "$STORAGE_ROOT" \
        --gid "$STORAGE_GROUP" \
        --shell /usr/sbin/nologin \
        "$STORAGE_USER"
fi

sudo install -d \
    -o "$STORAGE_USER" \
    -g "$STORAGE_GROUP" \
    -m 755 \
    "$STORAGE_ROOT"

# Save the global options in /etc/yiimpool.conf so that standalone
# tools know where to look for data.
echo 'STORAGE_USER='"${STORAGE_USER}"'
STORAGE_GROUP='"${STORAGE_GROUP}"'
STORAGE_ROOT='"${STORAGE_ROOT}"'
PUBLIC_IP='"${PUBLIC_IP}"'
PUBLIC_IPV6='"${PUBLIC_IPV6}"'
DISTRO='"${DISTRO}"'
FIRST_TIME_SETUP='"${FIRST_TIME_SETUP}"'
PRIVATE_IP='"${PRIVATE_IP}"'' | sudo -E tee /etc/yiimpool.conf >/dev/null 2>&1

cd ~
sudo setfacl -m u:${whoami}:rwx /home/${whoami}/sqsyiimp
clear
print_success "User $whoami is configured for SQSYIIMP (passwordless sudo, yiimpool command)"
print_warning "Reboot so group membership applies, then run: yiimpool"
exit 0
