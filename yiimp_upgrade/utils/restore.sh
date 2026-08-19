#!/usr/bin/env bash

#####################################################
# SQSYIIMP - SabiasQue.Space
#
# This script helps restore Yiimpool from a backup
#
# Author: SabiasQue.Space
# Date: 2025-02-06
#####################################################

source /etc/functions.sh
source /etc/yiimpool.conf
source $HOME/sqsyiimp/yiimp_upgrade/utils/functions.sh

main() {
    log_message "$YELLOW" "Starting Yiimpool restore process..."

    ls -lh $BACKUP_DIR/*.tar.gz 2>/dev/null || {
        log_message "$RED" "No backups found in $BACKUP_DIR"
        exit 1
    }

    echo -e "\nEnter the backup filename to restore (or 'exit' to quit):"
    read -r backup_choice

    if [ "$backup_choice" = "exit" ]; then
        log_message "$YELLOW" "Restore cancelled by user"
        exit 0
    fi

    backup_file="$BACKUP_DIR/$backup_choice"

    if [ ! -f "$backup_file" ]; then
        log_message "$RED" "Backup file not found: $backup_file"
        exit 1
    fi

    echo -e "\nWARNING: This will replace your current installation with the backup."
    echo -e "Are you sure you want to continue? (y/n)"
    read -r confirm

    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_message "$YELLOW" "Restore cancelled by user"
        exit 0
    fi

    if restore_from_backup "$backup_file"; then
        log_message "$GREEN" "Restore completed successfully!"
        log_message "$YELLOW" "Please restart your system to ensure all changes take effect."
    else
        log_message "$RED" "Restore failed. Please check the logs."
        exit 1
    fi
}

main
