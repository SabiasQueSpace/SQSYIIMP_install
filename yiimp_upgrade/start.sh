#!/usr/bin/env bash


#####################################################
# This is the entry point for configuring the system.
# Source https://mailinabox.email/ https://github.com/mail-in-a-box/mailinabox
# SQSYIIMP - SabiasQue.Space
#####################################################

source /etc/functions.sh # load our functions
source /etc/yiimpool.conf
# Ensure Python reads/writes files in UTF-8. If the machine
# triggers some other locale in Python, like ASCII encoding,
# Python may not be able to read/write files. This is also
# in the management daemon startup script and the cron script.

if ! locale -a | grep en_US.utf8 > /dev/null; then
# Generate locale if not exists
hide_output locale-gen en_US.UTF-8
fi

export LANGUAGE=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_TYPE=en_US.UTF-8

# Fix so line drawing characters are shown correctly in Putty on Windows. See #744.
export NCURSES_NO_UTF8_ACS=1

# Create the temporary installation directory if it doesn't already exist.
if [ ! -d "$STORAGE_ROOT/yiimp/yiimp_setup" ]; then
    print_status "Creating temporary YiiMP setup directory..."
    sudo mkdir -p "$STORAGE_ROOT/yiimp/yiimp_setup"
fi

# Start the upgrade menu.
source "$STORAGE_ROOT/yiimp/.yiimp.conf"
source upgrade_warning.sh
source menu.sh
