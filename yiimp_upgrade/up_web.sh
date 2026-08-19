#!/usr/bin/env bash

#####################################################
# SQSYIIMP - SabiasQue.Space
#####################################################

source /etc/functions.sh
source /etc/yiimpool.conf
source "$STORAGE_ROOT/yiimp/.yiimp.conf"

# If yiimp source already exists, remove it so we always get a fresh clone
if [[ -e "$STORAGE_ROOT/yiimp/yiimp_setup/yiimp" ]]; then
    sudo rm -rf "$STORAGE_ROOT/yiimp/yiimp_setup/yiimp"
fi
hide_output sudo git clone "${YiiMPRepo}" "$STORAGE_ROOT/yiimp/yiimp_setup/yiimp"

echo "Upgrading stratum..."
cd "$STORAGE_ROOT/yiimp/yiimp_setup/yiimp/web/yaamp/core/functions/"

cp -r yaamp.php "$STORAGE_ROOT/yiimp/site/web/yaamp/core/functions"

echo "Web upgrade complete..."
cd "$HOME/sqsyiimp/yiimp_upgrade"
