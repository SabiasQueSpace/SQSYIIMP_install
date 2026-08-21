#!/usr/bin/env bash

#
# This is for upgrading stratum.
#
# Author: SabiasQue.Space
#
# 2025-02-06
#

source /etc/functions.sh
source /etc/yiimpool.conf

STORAGE_USER="${STORAGE_USER:-crypto-data}"
STORAGE_GROUP="${STORAGE_GROUP:-${STORAGE_USER}}"
STORAGE_ROOT="${STORAGE_ROOT:-/home/${STORAGE_USER}}"

source "$STORAGE_ROOT/yiimp/.yiimp.conf"

STRATUM_DIR="$STORAGE_ROOT/yiimp/site/stratum"

YIIMP_DIR="$STORAGE_ROOT/yiimp/yiimp_setup/yiimp"
if [[ -d "$YIIMP_DIR" ]]; then
    sudo rm -rf "$YIIMP_DIR"
fi

echo -e "$GREEN Cloning fresh YiiMP repository... $NC"
if !  sudo git clone "${YiiMPRepo}" "$YIIMP_DIR"; then
    echo -e "$RED Failed to clone YiiMP repository. Exiting... $NC"
    exit 1
fi

echo -e "$GREEN Selecting a compatible stratum compiler... $NC"
select_stratum_compiler

echo
echo -e "$YELLOW => Upgrading stratum <= ${NC}"
echo
cd $YIIMP_DIR/stratum
sudo git submodule init
sudo git submodule update
cd secp256k1 && sudo chmod +x autogen.sh &&  sudo ./autogen.sh &&  sudo env CC="$STRATUM_CC" CXX="$STRATUM_CXX" ./configure --enable-experimental --enable-module-ecdh --with-bignum=no --enable-endomorphism &&  sudo env CC="$STRATUM_CC" CXX="$STRATUM_CXX" make -j"$(( $(nproc) + 1 ))"
cd $YIIMP_DIR/stratum

echo -e "$GREEN Building stratum... $NC"

if ! sudo env CC="$STRATUM_CC" CXX="$STRATUM_CXX" make -C algos -j"$(( $(nproc) + 1 ))"; then
    echo -e "$RED Failed to build stratum. Please check the build output above for errors. Exiting... $NC"
    exit 1
fi
echo -e "$GREEN algos built successfully! $NC"

if ! sudo env CC="$STRATUM_CC" CXX="$STRATUM_CXX" make -C sha3 -j"$(( $(nproc) + 1 ))"; then
    echo -e "$RED Failed to build sha3. Please check the build output above for errors. Exiting... $NC"
    exit 1
fi
echo -e "$GREEN sha3 built successfully! $NC"

if ! sudo env CC="$STRATUM_CC" CXX="$STRATUM_CXX" make -C iniparser -j"$(( $(nproc) + 1 ))"; then
    echo -e "$RED Failed to build iniparser. Please check the build output above for errors. Exiting... $NC"
    exit 1
fi
echo -e "$GREEN iniparser built successfully! $NC"

if ! sudo env CC="$STRATUM_CC" CXX="$STRATUM_CXX" make -j"$(( $(nproc) + 1 ))"; then
    echo -e "$RED Failed to build stratum. Please check the build output above for errors. Exiting... $NC"
    exit 1
fi
echo -e "$GREEN stratum built successfully! $NC"

echo -e "$GREEN Installing stratum... $NC"

# Install to a temporary path first and atomically replace the executable.
if ! sudo install \
    -o "$STORAGE_USER" \
    -g "$STORAGE_GROUP" \
    -m 755 \
    stratum \
    "$STRATUM_DIR/stratum.new"
then
    echo -e "$RED Failed to stage stratum binary. Exiting... $NC"
    exit 1
fi

if ! sudo mv -f \
    "$STRATUM_DIR/stratum.new" \
    "$STRATUM_DIR/stratum"
then
    echo -e "$RED Failed to install stratum. Exiting... $NC"
    exit 1
fi

sudo chown \
    "$STORAGE_USER:$STORAGE_GROUP" \
    "$STRATUM_DIR/stratum"

echo -e "$GREEN Copying yaamp.php to the site directory... $NC"
cd $YIIMP_DIR/web/yaamp/core/functions/
sudo install     -o "$STORAGE_USER"     -g www-data     -m 664     yaamp.php     "$STORAGE_ROOT/yiimp/site/web/yaamp/core/functions/yaamp.php"

echo -e "$GREEN Stratum upgrade completed successfully! $NC"
cd
