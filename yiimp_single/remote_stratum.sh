#!/usr/bin/env bash

##########################################
# SQSYIIMP - SabiasQue.Space
#
# This script compiles and sets up the
# Stratum server for a YiiMP cryptocurrency
# mining pool on a remote server. It builds
# necessary components such as blocknotify,
# iniparser, and stratum, sets up the file
# structure, and updates configuration files
# with appropriate database and server
# information.
#
# Author: SabiasQue.Space
# Date: 2026-03-06
##########################################

export TERM=xterm

# Load configuration files
source /etc/functions.sh
source /etc/yiimpool.conf
source "$STORAGE_ROOT/yiimp/.yiimp.conf"
source "$HOME/sqsyiimp/yiimp_single/.wireguard.install.cnf"

# Display terminal art and initial messages
term_art

# Navigate to the setup directory
cd "$STORAGE_ROOT/yiimp/yiimp_setup"

print_header "Compiler Setup"
print_status "Selecting a compatible C/C++ compiler"
hide_output sudo apt-get update
select_stratum_compiler
print_success "Compiler selected: $STRATUM_CC / $STRATUM_CXX"

print_header "Dependencies Installation"
print_status "Installing Stratum build dependencies"
apt_install_required \
    build-essential libtool autotools-dev automake pkg-config libssl-dev \
    libevent-dev bsdextrautils cmake libboost-all-dev zlib1g-dev \
    libseccomp-dev libcap-dev libminiupnpc-dev gettext libqrencode-dev \
    libzmq3-dev libgmp-dev default-libmysqlclient-dev libcurl4-openssl-dev \
    libsodium-dev autoconf
apt_install_optional p7zip-full libcanberra-gtk-module

print_status "Compiling blocknotify and iniparser"

# Compile blocknotify
cd "$STORAGE_ROOT/yiimp/yiimp_setup"/yiimp/blocknotify
sudo sed -i "s/tu8tu5/$BlocknotifyPassword/" blocknotify.cpp
hide_output sudo env CC="$STRATUM_CC" CXX="$STRATUM_CXX" make -j"$(nproc)"

print_status "Building stratum"
cd "$STORAGE_ROOT/yiimp/yiimp_setup"/yiimp/stratum
hide_output sudo git submodule init
hide_output sudo git submodule update
hide_output sudo env CC="$STRATUM_CC" CXX="$STRATUM_CXX" make -C algos
hide_output sudo env CC="$STRATUM_CC" CXX="$STRATUM_CXX" make -C sha3
hide_output sudo env CC="$STRATUM_CC" CXX="$STRATUM_CXX" make -C iniparser

print_status "Configuring and building secp256k1"
cd secp256k1
sudo chmod +x autogen.sh
hide_output sudo ./autogen.sh
hide_output sudo env CC="$STRATUM_CC" CXX="$STRATUM_CXX" ./configure --enable-experimental --enable-module-ecdh --with-bignum=no --enable-endomorphism
hide_output sudo env CC="$STRATUM_CC" CXX="$STRATUM_CXX" make -j"$(( $(nproc) + 1 ))"

print_status "Building main stratum"
cd "$STORAGE_ROOT/yiimp/yiimp_setup"/yiimp/stratum
hide_output sudo env CC="$STRATUM_CC" CXX="$STRATUM_CXX" make -j"$(( $(nproc) + 1 ))"

print_header "File Structure Setup"
print_status "Creating stratum directory structure"
cd $STORAGE_ROOT/yiimp/yiimp_setup/yiimp/stratum
sudo cp -a config.sample/. $STORAGE_ROOT/yiimp/site/stratum/config
sudo cp -r stratum run.sh $STORAGE_ROOT/yiimp/site/stratum

cd $STORAGE_ROOT/yiimp/yiimp_setup/yiimp
sudo cp blocknotify/blocknotify $STORAGE_ROOT/yiimp/site/stratum
sudo cp blocknotify/blocknotify /usr/bin

print_status "Installing Stratum management tools"
bash "$HOME/sqsyiimp/stratum_manager/install.sh"

print_header "Stratum Database Configuration"
print_status "Updating stratum configuration with database credentials"
cd "$STORAGE_ROOT/yiimp/site/stratum/config"

sudo sed -i "s/password = tu8tu5/password = $BlocknotifyPassword/g" *.conf
sudo sed -i "s/server = yaamp.com/server = $StratumURL/g" *.conf
if [[ ("$wireguard" == "true") ]]; then
    print_info "Configuring for WireGuard: Using internal IP ${DBInternalIP}"
    sudo sed -i "s/host = yaampdb/host = $DBInternalIP/g" *.conf
else
    print_info "Configuring for local setup: Using localhost"
    sudo sed -i "s/host = yaampdb/host = localhost/g" *.conf
fi
sudo sed -i "s/database = yaamp/database = $YiiMPDBName/g" *.conf
sudo sed -i "s/username = root/username = $StratumDBUser/g" *.conf
sudo sed -i "s/password = patofpaq/password = $StratumUserDBPassword/g" *.conf

print_status "Synchronizing Stratum coinbase identity from YiiMP"
if POOL_COINBASE_TAG="$(get_pool_coinbase_tag)"; then
    if apply_coinbaseextra_to_configs "$STORAGE_ROOT/yiimp/site/stratum/config" "$POOL_COINBASE_TAG"; then
        print_success "coinbaseextra synchronized: $POOL_COINBASE_TAG"
    else
        print_warning "Unable to synchronize coinbaseextra; existing Stratum configuration was left unchanged"
    fi
else
    print_warning "Unable to resolve YAAMP_SITE_NAME; coinbaseextra was not changed"
fi

print_status "Setting directory permissions"
sudo setfacl -m u:"$USER":rwx "$STORAGE_ROOT/yiimp/site/stratum/"
sudo setfacl -m u:"$USER":rwx "$STORAGE_ROOT/yiimp/site/stratum/config"

# copy blocknotify to daemon servers
# set daemon user and password
DaemonUser=${DaemonUser}
DaemonPass="${DaemonPass}"
DaemonServer=${DaemonInternalIP}

# set script paths
script_blocknotify="${STORAGE_ROOT}/yiimp/site/stratum/blocknotify"

# Desired location of the scripts on the remote server.
remote_script_blocknotify_path="/tmp/blocknotify"

# set ssh Stratum
SSH_ASKPASS_SCRIPT=/tmp/ssh-askpass-script
cat > ${SSH_ASKPASS_SCRIPT} <<EOL
#!/usr/bin/env bash
echo '${DaemonPass}'
EOL
chmod u+x ${SSH_ASKPASS_SCRIPT}

# Set no display, necessary for ssh to play nice with setsid and SSH_ASKPASS.
export DISPLAY=:0

# Tell SSH to read in the output of the provided script as the password.
# We still have to use setsid to eliminate access to a terminal and thus avoid
# it ignoring this and asking for a password.
export SSH_ASKPASS=${SSH_ASKPASS_SCRIPT}

# LogLevel error is to suppress the hosts warning. The others are
# necessary if working with development servers with self-signed
# certificates.
SSH_OPTIONS="-oLogLevel=error"
SSH_OPTIONS="${SSH_OPTIONS} -oStrictHostKeyChecking=no"
SSH_OPTIONS="${SSH_OPTIONS} -oUserKnownHostsFile=/dev/null"

# Load in a base 64 encoded version of the script.
B64_blocknotify=$(base64 --wrap=0 "${script_blocknotify}")

# The command that will run remotely. This unpacks the
# base64-encoded script, makes it executable, and then
# executes it as a background task.
blocknotify="base64 -d - > ${remote_script_blocknotify_path} <<< ${B64_blocknotify};"
blocknotify="${blocknotify} chmod +x ${remote_script_blocknotify_path}; > /dev/null 2>&1 &"

# Execute scripts on remote server
setsid ssh ${SSH_OPTIONS} ${DaemonUser}@${DaemonServer} "${blocknotify}"

print_header "Installation Summary"
print_success "Remote stratum server build completed successfully"
print_info "Stratum URL: $StratumURL"
print_info "Installation Directory: $STORAGE_ROOT/yiimp/site/stratum"
print_info "Configuration Directory: $STORAGE_ROOT/yiimp/site/stratum/config"
print_info "Blocknotify Location: /usr/bin/blocknotify"

print_divider

exit 0
