#!/usr/bin/env bash

#####################################################
# SQSYIIMP - SabiasQue.Space
#####################################################
# Needs to be ran after the first reboot of the system after permissions are set
#####################################################

source /etc/yiimpool.conf
source /etc/functions.sh

sleep 5
hide_output yiimp checkup

# Prevents error when trying to log in to admin panel the first time...

sudo touch $STORAGE_ROOT/yiimp/site/log/debug.log
sudo chmod 755 $STORAGE_ROOT/yiimp/site/log
sudo chmod 644 $STORAGE_ROOT/yiimp/site/log/debug.log
sudo chown -R www-data:www-data $STORAGE_ROOT/yiimp/site/log

# Delete me no longer needed after it runs the first time

sudo rm -r $STORAGE_ROOT/yiimp/first_boot.sh
cd $HOME/sqsyiimp/yiimp_single
