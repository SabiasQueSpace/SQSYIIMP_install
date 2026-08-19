#!/usr/bin/env bash

##########################################
# SQSYIIMP - SabiasQue.Space
#
# Checks GitHub for a new SQSYIIMP release
# and upgrades the installer if one is available.
# This is the entry point for the full upgrade
# flow initiated from the Options menu.
#
# Author: SabiasQue.Space
# Date: 2026-03-06
##########################################

source /etc/functions.sh
source /etc/yiimpool.conf
source /etc/yiimpoolversion.conf
source $HOME/sqsyiimp/yiimp_upgrade/utils/functions.sh

print_header "SQSYIIMP Installer Upgrade"

log_message "$YELLOW" "Current version : $VERSION"
log_message "$YELLOW" "Checking GitHub for the latest release..."
echo

LATEST_TAG=$(get_latest_release) || {
    log_message "$RED" "Could not reach GitHub. Check your internet connection and try again."
    exit 1
}

# Already up to date
if [ "$LATEST_TAG" = "$VERSION" ]; then
    log_message "$GREEN" "SQSYIIMP is already up to date."
    log_message "$GREEN" "Installed version : $VERSION"
    exit 0
fi

log_message "$GREEN" "New release available: $LATEST_TAG  (you have: $VERSION)"
echo

# Show a changelog preview (commits between current and latest tag)
log_message "$YELLOW" "Recent changes in $LATEST_TAG:"
cd "$HOME/sqsyiimp"
git fetch --depth 1 --force --prune origin tag "${LATEST_TAG}" 2>/dev/null || true
git log --oneline "${VERSION}..${LATEST_TAG}" 2>/dev/null \
    || echo "  (local changelog not available — check GitHub for release notes)"
echo

# Confirmation dialog
if ! dialog --stdout --title "SQSYIIMP Upgrade Available" \
    --yesno "\
A new version of SQSYIIMP is available!\n\
\n\
  Current version : $VERSION\n\
  New version     : $LATEST_TAG\n\
\n\
The upgrade will:\n\
\n\
  1. Verify all services are running\n\
  2. Create a backup of your current configuration\n\
  3. Download and apply the new release from GitHub\n\
  4. Verify services after the upgrade\n\
\n\
Your pool data, stratum config, and database\n\
will NOT be modified by this upgrade.\n\
\n\
Do you want to upgrade now?" \
    20 65; then
    log_message "$YELLOW" "Upgrade cancelled."
    exit 0
fi

clear

# Run the full upgrade
cd "$HOME/sqsyiimp/yiimp_upgrade"
source upgrade.sh
