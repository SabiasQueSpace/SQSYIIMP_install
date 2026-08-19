#!/usr/bin/env bash

#####################################################
# Source: https://mailinabox.email/ https://github.com/mail-in-a-box/mailinabox
# SQSYIIMP - SabiasQue.Space
#####################################################

# Load required functions and configurations
source /etc/functions.sh
source /etc/yiimpool.conf
source "$STORAGE_ROOT/yiimp/.yiimp.conf"


set -eu -o pipefail

# Function to print error messages
print_error() {
    local line file
    read -r line file <<< "$(caller)"
    echo "Error in line $line of file $file:" >&2
    sed "${line}q;d" "$file" >&2
}

trap print_error ERR

# Display banner
term_art

print_header "Self-Signed SSL Certificate Generation"

print_status "Checking OpenSSL installation"
hide_output sudo apt install -y  openssl


print_header "SSL Directory Setup"
print_status "Creating SSL directory structure"
sudo mkdir -p "$STORAGE_ROOT/ssl"
print_success "SSL directory created at $STORAGE_ROOT/ssl"

print_header "Private Key Generation"
if [ ! -f "$STORAGE_ROOT/ssl/ssl_private_key.pem" ]; then
    print_status "Generating new 2048-bit private key"
    (
        umask 077
        hide_output sudo openssl genrsa -out "$STORAGE_ROOT/ssl/ssl_private_key.pem" 2048
    )
    print_success "Private key generated successfully"
else
    print_info "Using existing private key"
fi

print_header "SSL Certificate Generation"
if [ ! -f "$STORAGE_ROOT/ssl/ssl_certificate.pem" ]; then
    print_status "Creating certificate signing request"
    CSR="/tmp/ssl_cert_sign_req-$RANDOM.csr"
    hide_output sudo openssl req -new -key "$STORAGE_ROOT/ssl/ssl_private_key.pem" -out "$CSR" \
        -sha256 -subj "/CN=$PRIMARY_HOSTNAME"

    print_status "Generating self-signed certificate"
    CERT="$STORAGE_ROOT/ssl/$PRIMARY_HOSTNAME-selfsigned-$(date --rfc-3339=date | tr -d '-').pem"
    hide_output sudo openssl x509 -req -days 365 -in "$CSR" -signkey "$STORAGE_ROOT/ssl/ssl_private_key.pem" -out "$CERT"

    print_status "Cleaning up and linking certificate"
    sudo rm -f "$CSR"
    sudo ln -s "$CERT" "$STORAGE_ROOT/ssl/ssl_certificate.pem"
    print_success "SSL certificate generated and linked"
else
    print_info "Using existing SSL certificate"
fi

# Generate Diffie-Hellman cipher bits if not already generated
if [ ! -f /etc/nginx/dhparam.pem ]; then
    print_status "Generating 2048-bit Diffie-Hellman parameters (this may take some time)"
    hide_output sudo openssl dhparam -out /etc/nginx/dhparam.pem 2048
    print_success "Diffie-Hellman parameters generated"
else
    print_info "Using existing Diffie-Hellman parameters"
fi

print_header "SSL Configuration Summary"
print_info "SSL Private Key: $STORAGE_ROOT/ssl/ssl_private_key.pem"
print_info "SSL Certificate: $STORAGE_ROOT/ssl/ssl_certificate.pem"
print_info "DH Parameters: /etc/nginx/dhparam.pem"
print_info "Hostname: $PRIMARY_HOSTNAME"
print_info "Validity: 365 days"

print_success "Self-signed SSL configuration completed successfully"

cd $HOME/sqsyiimp/yiimp_single
