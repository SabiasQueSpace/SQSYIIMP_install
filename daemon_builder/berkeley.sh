#!/usr/bin/env bash

#####################################################
# SQSYIIMP - SabiasQue.Space
#
# This script builds and installs various versions of
# Berkeley DB and related components required for
# cryptocurrency daemon compilation. It includes
# BDB 4.8, 5.1, 5.3, 6.2, 18, OpenSSL, and
# bls-signatures.
#
# Author: SabiasQue.Space
# Date: 2024-07-15
#####################################################

# Source configuration files
source /etc/yiimpoolversion.conf
source /etc/functions.sh
source /etc/yiimpool.conf

# Set variables
STRATUM_DIR="$STORAGE_ROOT/yiimp/site/stratum"
FUNCTIONFILE="daemonbuilder.sh"
TAG="$VERSION"

# Display banner
term_art

print_header "Berkeley DB Build Environment Setup"

print_status "Initializing build environment..."
sudo mkdir -p $STORAGE_ROOT/yiimp/yiimp_setup/tmp
cd $STORAGE_ROOT/yiimp/yiimp_setup/tmp

print_status "Updating configuration files..."
sleep 1
#sudo sed -i 's#absolutepathserver#'"$absolutepath"'#' conf/daemonbuilder.sh
print_success "Configuration updated successfully"

print_header "Berkeley DB 4.8 Installation"
print_status "Building Berkeley DB 4.8..."
sudo mkdir -p $STORAGE_ROOT/berkeley/db4/
hide_output sudo wget -O db-4.8.30.NC.tar.gz 'https://download.oracle.com/berkeley-db/db-4.8.30.NC.tar.gz'
printf '%s  %s\n' '12edc0df75bf9abd7f82f821795bcee50f42cb2e5f76a6a281b85732798364ef' 'db-4.8.30.NC.tar.gz' | sha256sum -c -
hide_output sudo tar -xzvf db-4.8.30.NC.tar.gz
sudo sed -i 's/__atomic_compare_exchange/__atomic_compare_exchange_db/g' db-4.8.30.NC/dbinc/atomic.h
cd db-4.8.30.NC/build_unix/
hide_output sudo ../dist/configure --enable-cxx --disable-shared --with-pic --prefix=$STORAGE_ROOT/berkeley/db4
hide_output sudo make -j$((`nproc`+1))
hide_output sudo make install -j$((`nproc`+1))
cd $STORAGE_ROOT/yiimp/yiimp_setup/tmp
sudo rm -r db-4.8.30.NC.tar.gz db-4.8.30.NC
print_success "Berkeley DB 4.8 installed successfully"

print_header "Berkeley DB 5.1 Installation"
print_status "Building Berkeley DB 5.1..."
sudo mkdir -p $STORAGE_ROOT/berkeley/db5.1/
hide_output sudo wget 'https://download.oracle.com/berkeley-db/db-5.1.29.tar.gz'
hide_output sudo tar -xzvf db-5.1.29.tar.gz
sudo sed -i 's/__atomic_compare_exchange/__atomic_compare_exchange_db/g' db-5.1.29/src/dbinc/atomic.h
cd db-5.1.29/build_unix/
hide_output sudo ../dist/configure --enable-cxx --disable-shared --with-pic --prefix=$STORAGE_ROOT/berkeley/db5.1
hide_output sudo make -j$((`nproc`+1))
hide_output sudo make install -j$((`nproc`+1))
cd $STORAGE_ROOT/yiimp/yiimp_setup/tmp
sudo rm -r db-5.1.29.tar.gz db-5.1.29
print_success "Berkeley DB 5.1 installed successfully"

print_header "Berkeley DB 5.3 Installation"
print_status "Building Berkeley DB 5.3..."
sudo mkdir -p $STORAGE_ROOT/berkeley/db5.3/
hide_output sudo wget 'http://anduin.linuxfromscratch.org/BLFS/bdb/db-5.3.28.tar.gz'
hide_output sudo tar -xzvf db-5.3.28.tar.gz
sudo sed -i 's/__atomic_compare_exchange/__atomic_compare_exchange_db/g' db-5.3.28/src/dbinc/atomic.h
cd db-5.3.28/build_unix/
hide_output sudo ../dist/configure --enable-cxx --disable-shared --with-pic --prefix=$STORAGE_ROOT/berkeley/db5.3
hide_output sudo make -j$((`nproc`+1))
hide_output sudo make install -j$((`nproc`+1))
cd $STORAGE_ROOT/yiimp/yiimp_setup/tmp
sudo rm -r db-5.3.28.tar.gz db-5.3.28
print_success "Berkeley DB 5.3 installed successfully"

print_header "Berkeley DB 6.2 Installation"
print_status "Building Berkeley DB 6.2..."
sudo mkdir -p $STORAGE_ROOT/berkeley/db6.2/
hide_output sudo wget 'https://download.oracle.com/berkeley-db/db-6.2.32.tar.gz'
hide_output sudo tar -xzvf db-6.2.32.tar.gz
sudo sed -i 's/__atomic_compare_exchange/__atomic_compare_exchange_db/g' db-6.2.32/src/dbinc/atomic.h
cd db-6.2.32/build_unix/
hide_output sudo ../dist/configure --enable-cxx --disable-shared --with-pic --prefix=$STORAGE_ROOT/berkeley/db6.2
hide_output sudo make -j$((`nproc`+1))
hide_output sudo make install -j$((`nproc`+1))
cd $STORAGE_ROOT/yiimp/yiimp_setup/tmp
sudo rm -r db-6.2.32.tar.gz db-6.2.32
print_success "Berkeley DB 6.2 installed successfully"

print_header "Berkeley DB 18 Installation"
print_status "Building Berkeley DB 18..."
sudo mkdir -p $STORAGE_ROOT/berkeley/db18/
hide_output sudo wget 'https://download.oracle.com/berkeley-db/db-18.1.40.tar.gz'
hide_output sudo tar -xzvf db-18.1.40.tar.gz
cd db-18.1.40/build_unix/
hide_output sudo ../dist/configure --enable-cxx --disable-shared --with-pic --prefix=$STORAGE_ROOT/berkeley/db18
hide_output sudo make -j$((`nproc`+1))
hide_output sudo make install -j$((`nproc`+1))
cd $STORAGE_ROOT/yiimp/yiimp_setup/tmp
sudo rm -r db-18.1.40.tar.gz db-18.1.40
print_success "Berkeley DB 18 installed successfully"

print_header "OpenSSL 1.0.2g Installation"
print_status "Building OpenSSL 1.0.2g..."
cd $STORAGE_ROOT/yiimp/yiimp_setup/tmp
hide_output sudo wget https://www.openssl.org/source/old/1.0.2/openssl-1.0.2g.tar.gz --no-check-certificate
hide_output sudo tar -xf openssl-1.0.2g.tar.gz
cd openssl-1.0.2g
hide_output sudo ./config --prefix=$STORAGE_ROOT/openssl --openssldir=$STORAGE_ROOT/openssl shared zlib
hide_output sudo make -j$((`nproc`+1))
hide_output sudo make install -j$((`nproc`+1))
cd $STORAGE_ROOT/yiimp/yiimp_setup/tmp
sudo rm -r openssl-1.0.2g.tar.gz openssl-1.0.2g
print_success "OpenSSL 1.0.2g installed successfully"

print_header "BLS Signatures Installation"
print_status "Building bls-signatures..."
cd $STORAGE_ROOT/yiimp/yiimp_setup/tmp
hide_output sudo wget 'https://github.com/codablock/bls-signatures/archive/v20181101.zip'
hide_output sudo unzip v20181101.zip
cd bls-signatures-20181101
hide_output sudo cmake .
hide_output sudo make install -j$((`nproc`+1))
cd $STORAGE_ROOT/yiimp/yiimp_setup/tmp
sudo rm -r v20181101.zip bls-signatures-20181101
print_success "BLS signatures installed successfully"

print_header "Blocknotify Setup"
print_status "Configuring blocknotify script..."
if [[ ("$wireguard" == "true") ]]; then
    source $STORAGE_ROOT/yiimp/.wireguard.conf
    echo '#!/bin/bash
#####################################################
# SQSYIIMP - SabiasQue.Space
#####################################################
blocknotify '""''"${DBInternalIP}"''""':$1 $2 $3' | sudo -E tee /usr/bin/blocknotify.sh >/dev/null 2>&1
else
    echo '#!/bin/bash
#####################################################
# SQSYIIMP - SabiasQue.Space
#####################################################
blocknotify 127.0.0.1:$1 $2 $3' | sudo -E tee /usr/bin/blocknotify.sh >/dev/null 2>&1
fi
sudo chmod +x /usr/bin/blocknotify.sh
print_success "Blocknotify script configured successfully"

print_header "DaemonBuilder Installation"
print_status "Setting up DaemonBuilder..."
cd $HOME/sqsyiimp/daemon_builder
sudo mkdir -p conf
# Install the canonical DaemonBuilder runtime files.
sudo mkdir -p "$STORAGE_ROOT/daemon_builder"
sudo cp -r "$HOME/sqsyiimp/daemon_builder/utils"/. "$STORAGE_ROOT/daemon_builder"/
sudo cp -r $HOME/sqsyiimp/daemon_builder/conf/daemonbuilder.sh /etc/

# Install the descriptive Stratum manager command, runtime resolver, and
# compatibility aliases used by existing DaemonBuilder workflows.
sudo chmod +x $STORAGE_ROOT/daemon_builder/*
if [ -d "$STRATUM_DIR" ]; then
    print_status "Installing SQSYIIMP Stratum management tools..."
    bash "$HOME/sqsyiimp/stratum_manager/install.sh"
fi

print_status "Creating DaemonBuilder command..."
echo '#!/usr/bin/env bash
source /etc/yiimpool.conf
source /etc/functions.sh
cd $STORAGE_ROOT/daemon_builder
bash start.sh
cd ~' | sudo -E tee /usr/bin/daemonbuilder >/dev/null 2>&1
sudo chmod +x /usr/bin/daemonbuilder

print_status "Setting up configuration directory..."
if [ ! -d "$STORAGE_ROOT/daemon_builder/conf" ]; then
    sudo mkdir -p $STORAGE_ROOT/daemon_builder/conf
fi

print_status "Creating info.sh configuration..."
CURRENT_USER=$(whoami)

sudo tee "$STORAGE_ROOT/daemon_builder/conf/info.sh" >/dev/null 2>&1 <<EOF
#!/bin/sh
USERSERVER="${CURRENT_USER}"
VERSION="${TAG}"

PATH_STRATUM="${STRATUM_DIR}"
FUNCTION_FILE="${FUNCTIONFILE}"
EOF

sudo chmod +x "$STORAGE_ROOT/daemon_builder/conf/info.sh"

print_header "Installation Summary"
print_info "Berkeley DB Versions: 4.8, 5.1, 5.3, 6.2, 18"
print_info "OpenSSL Version: 1.0.2g"
print_info "BLS Signatures: v20181101"
print_info "DaemonBuilder: Configured"
print_info "Blocknotify: Installed"
print_success "Berkeley DB and components installation completed successfully"

print_divider

cd $HOME/sqsyiimp/yiimp_single
