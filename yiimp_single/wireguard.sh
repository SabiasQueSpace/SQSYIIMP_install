#!/usr/bin/env bash

#####################################################
# SQSYIIMP - SabiasQue.Space
#
# This script installs and configures WireGuard
# for secure VPN communication. It sets up
# necessary keys, configuration files, and
# ensures the service is started and enabled
# at boot.
#
# Author: SabiasQue.Space
# Date: 2024-07-15
#####################################################

# Load configuration files
source $HOME/sqsyiimp/yiimp_single/.wireguard.install.cnf
source $STORAGE_ROOT/yiimp/.wireguard.conf
source /etc/functions.sh
source /etc/yiimpool.conf

# Display banner
term_art

print_header "WireGuard Installation"


hide_output sudo apt-get update
hide_output sudo apt-get install -y wireguard

print_header "WireGuard Key Generation"
print_status "Generating WireGuard keys..."
wg_private_key=$(wg genkey)
wg_public_key=$(echo "$wg_private_key" | wg pubkey)
print_success "WireGuard keys generated successfully"

print_header "WireGuard Configuration"
print_status "Creating WireGuard configuration file..."
wg_config="/etc/wireguard/wg0.conf"
sudo tee "$wg_config" >/dev/null <<EOL
[Interface]
PrivateKey = $wg_private_key
ListenPort = 6121
SaveConfig = true
Address = ${DBInternalIP}/24
EOL
print_success "WireGuard configuration file created"

print_header "Service Configuration"
print_status "Starting WireGuard service..."
sudo systemctl start wg-quick@wg0
print_status "Enabling WireGuard service at boot..."
sudo systemctl enable wg-quick@wg0

print_status "Configuring firewall..."
if [ -z "${DISABLE_FIREWALL:-}" ]; then
    hide_output sudo apt-get install -y ufw

    print_status "Configuring firewall rules..."
    ufw_allow ssh
    print_success "SSH port opened"

    ufw_allow http
    print_success "HTTP port opened"

    ufw_allow https
    print_success "HTTPS port opened"

    ufw_allow 6121
    print_success "WireGuard port opened"

    SSH_PORT=$(sshd -T 2>/dev/null | grep "^port " | sed "s/port //")
    if [ ! -z "$SSH_PORT" ] && [ "$SSH_PORT" != "22" ]; then
        print_status "Opening alternate SSH port: $SSH_PORT"
        ufw_allow $SSH_PORT
        print_success "Alternate SSH port opened"
    fi

    hide_output sudo ufw --force enable
    print_success "Firewall enabled and configured"
fi

print_success "Firewall configured for WireGuard"

print_header "WireGuard Summary"
print_status "Saving WireGuard public information..."
dbpublic="${PUBLIC_IP}"
mypublic="${wg_public_key}"
echo -e "Public IP: ${dbpublic}\nPublic Key: ${mypublic}" | sudo -E tee "$STORAGE_ROOT/yiimp/.wireguard_public.conf" >/dev/null 2>&1

print_info "WireGuard Configuration Details:"
print_info "Public IP: ${dbpublic}"
print_info "Public Key: ${mypublic}"
print_info "Listen Port: 6121"
print_info "Configuration: ${wg_config}"

print_success "WireGuard setup completed successfully"

print_divider

cd $HOME/sqsyiimp/yiimp_single
