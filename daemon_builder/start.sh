#!/usr/bin/env bash

##################################################################################
# This is the entry point for configuring the system.                            #
# Source https://mailinabox.email/ https://github.com/mail-in-a-box/mailinabox   #
# SQSYIIMP - SabiasQue.Space
##################################################################################

source /etc/functions.sh
source /etc/yiimpool.conf

# Create DaemonBuilder directory
if [ ! -d $STORAGE_ROOT/daemon_builder ]; then
sudo mkdir -p $STORAGE_ROOT/daemon_builder
fi

if [[ "$DISTRO" == "24" || "$DISTRO" == "22" ]]; then
    sudo chmod 755 $STORAGE_ROOT/daemon_builder
fi
# Start the DeamonBuilder installation.
cd $HOME/sqsyiimp/daemon_builder
source requirements.sh

cd $HOME/sqsyiimp/yiimp_single