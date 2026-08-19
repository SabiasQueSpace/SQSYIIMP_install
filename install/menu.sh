#!/usr/bin/env bash

#
# SQSYIIMP Menu Script
#
# Author: SabiasQue.Space
# Updated: 2026-03-06
#

# Load configuration and functions
source /etc/yiimpool.conf
source /etc/yiimpoolversion.conf
source /etc/functions.sh

display_version_info

RESULT=$(dialog --stdout --nocancel --default-item 1 --backtitle "SQSYIIMP • SabiasQue.Space" --title "Main menu • $VERSION" --menu "Choose an installation or maintenance task" -1 66 6 \
    ' ' "═══════════  SQSYIIMP Installer ═══════════" \
    1 "Install YiiMP Single Server" \
    2 "Manage & Upgrade Options" \
    3 "Exit")

case "$RESULT" in
    1)
        clear
        print_header "YiiMP single-server install"
        print_status "Starting the WireGuard prompt and pool installer (this can take a long time)"
        cd $HOME/sqsyiimp/yiimp_single
        source start.sh
        ;;
    2)
        clear
        print_header "Manage and upgrade"
        cd $HOME/sqsyiimp/install
        source options.sh
        ;;
    3)
        clear
        motd
        print_success "Exited SQSYIIMP menu"
        print_info "Run yiimpool anytime to open this menu again"
        exit 0
        ;;
esac