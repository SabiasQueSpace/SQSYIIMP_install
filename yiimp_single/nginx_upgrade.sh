#!/usr/bin/env bash

#####################################################
# SQSYIIMP - SabiasQue.Space
#
# This script configures and upgrades NGINX for a
# YiiMP pool setup, and handles database tweaks.
#
# Author: SabiasQue.Space
# Date: 2024-07-15
#####################################################

# Load configuration files
source /etc/functions.sh
source /etc/yiimpool.conf
source "$STORAGE_ROOT/yiimp/.yiimp.conf"
source "$HOME/sqsyiimp/yiimp_single/.wireguard.install.cnf"

cd $HOME/sqsyiimp/yiimp_single

# Ensure the script exits on error and logs errors
set -eu -o pipefail

function print_error {
    read -r line file <<<$(caller)
    echo "An error occurred in line $line of file $file:" >&2
    sed "${line}q;d" "$file" >&2
}
trap print_error ERR

# Display banner
term_art

print_header "NGINX Installation and Configuration"

# Load WireGuard configuration if enabled
if [[ ("$wireguard" == "true") ]]; then
    source "$STORAGE_ROOT/yiimp/.wireguard.conf"
fi

print_header "Repository Setup"
print_status "Adding NGINX signing key..."
sudo curl -fsSL https://nginx.org/keys/nginx_signing.key | sudo gpg --dearmor -o /etc/apt/keyrings/nginx.gpg

# Add NGINX repository based on distribution
if [[ "$DISTRO" == "12" || "$DISTRO" == "11" ]]; then
    print_status "Configuring Debian repository..."
    echo "deb [signed-by=/etc/apt/keyrings/nginx.gpg] http://nginx.org/packages/mainline/debian $(lsb_release -cs) nginx" \
        | sudo tee /etc/apt/sources.list.d/nginx.list >/dev/null 2>&1
else
    print_status "Configuring Ubuntu repository..."
    echo "deb [signed-by=/etc/apt/keyrings/nginx.gpg] http://nginx.org/packages/mainline/ubuntu $(lsb_release -cs) nginx" \
        | sudo tee /etc/apt/sources.list.d/nginx.list >/dev/null 2>&1
fi

print_header "Package Installation"
print_status "Updating package lists..."
hide_output sudo apt-get update

print_status "Installing NGINX..."
hide_output sudo apt-get install -y nginx

print_header "Configuration Setup"
print_status "Creating configuration directories..."
sudo mkdir -p /etc/nginx/yiimpool

print_status "Backing up original configuration..."
sudo mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.old

print_status "Installing configuration files..."
sudo cp nginx_confs/nginx.conf /etc/nginx/
sudo cp nginx_confs/phpmyadmin.conf /etc/nginx/
sudo cp nginx_confs/general.conf /etc/nginx/yiimpool
sudo cp nginx_confs/php_fastcgi.conf /etc/nginx/yiimpool
sudo cp nginx_confs/security.conf /etc/nginx/yiimpool
sudo cp nginx_confs/letsencrypt.conf /etc/nginx/yiimpool

print_status "Removing default site configurations..."
sudo rm -f /etc/nginx/sites-enabled/default
sudo rm -f /etc/nginx/sites-available/default*

print_success "NGINX installation and configuration completed"

print_header "Service Restart"
print_status "Restarting NGINX..."
restart_service nginx
print_status "Restarting PHP-FPM..."
restart_service php8.1-fpm

print_divider

set +eu +o pipefail

cd $HOME/sqsyiimp/yiimp_single
