#!/usr/bin/env bash

##########################################
# SQSYIIMP - SabiasQue.Space
#
# Orchestrates full or stratum-only upgrades
# for an existing SQSYIIMP installation.
#
# Usage:
#   source upgrade.sh               # Full installer upgrade
#   source upgrade.sh --stratum-only  # Stratum recompile only
#
# Author: SabiasQue.Space
# Date: 2026-03-06
##########################################

source /etc/functions.sh
source /etc/yiimpool.conf
source /etc/yiimpoolversion.conf
source $HOME/sqsyiimp/yiimp_upgrade/utils/functions.sh

UPGRADE_TYPE="full"
if [ "${1:-}" == "--stratum-only" ]; then
    UPGRADE_TYPE="stratum"
fi

main() {
    log_message "$YELLOW" "Starting SQSYIIMP upgrade..."
    log_message "$YELLOW" "Current version : $VERSION"
    log_message "$YELLOW" "Upgrade type    : $UPGRADE_TYPE"
    echo

    if ! verify_requirements; then
        log_message "$RED" "System requirements not met. Aborting upgrade."
        exit 1
    fi

    # For a full installer upgrade, validate the Git repository before
    # spending time creating a backup.
    if [[ "$UPGRADE_TYPE" == "full" ]]; then
        cd "$HOME/sqsyiimp" || {
            log_message "$RED" "SQSYIIMP repository not found."
            exit 1
        }

        if [[ -n "$(git status --porcelain)" ]]; then
            log_message "$RED" "SQSYIIMP repository contains uncommitted changes."
            log_message "$RED" "Commit or restore them before running the updater."
            exit 1
        fi

        CURRENT_BRANCH="$(git branch --show-current)"

        if [[ "$CURRENT_BRANCH" != "main" ]]; then
            log_message "$RED" "Updater requires branch main (current: ${CURRENT_BRANCH:-detached HEAD})."
            exit 1
        fi
    fi

    backup_system

    case "$UPGRADE_TYPE" in
        "full")
            log_message "$YELLOW" "Fetching latest SQSYIIMP release from GitHub..."
            LATEST_TAG=$(get_latest_release) || {
                log_message "$RED" "Failed to fetch latest release. Aborting."
                exit 1
            }

            if [ "$LATEST_TAG" = "$VERSION" ]; then
                log_message "$GREEN" "SQSYIIMP is already up to date ($VERSION). No upgrade needed."
                exit 0
            fi

            log_message "$YELLOW" "Upgrading SQSYIIMP: $VERSION → $LATEST_TAG"
            echo

            cd "$HOME/sqsyiimp" || {
                log_message "$RED" "SQSYIIMP repository not found."
                exit 1
            }

            # Never overwrite local development/custom changes.
            if [[ -n "$(git status --porcelain)" ]]; then
                log_message "$RED" "SQSYIIMP repository contains uncommitted changes."
                log_message "$RED" "Commit or restore them before running the updater."
                exit 1
            fi

            CURRENT_BRANCH="$(git branch --show-current)"

            if [[ "$CURRENT_BRANCH" != "main" ]]; then
                log_message "$RED" "Updater requires branch main (current: ${CURRENT_BRANCH:-detached HEAD})."
                exit 1
            fi

            OLD_HEAD="$(git rev-parse HEAD)"

            log_message "$YELLOW" "Fetching release $LATEST_TAG from GitHub..."

            REPO_DIR="$HOME/sqsyiimp"
            REPO_OWNER="$(stat -c '%U' "$REPO_DIR" 2>/dev/null)"
            REPO_GROUP="$(stat -c '%G' "$REPO_DIR" 2>/dev/null)"

            if [[ -z "$REPO_OWNER" || -z "$REPO_GROUP" ]]; then
                log_message "$RED" "Could not determine SQSYIIMP repository owner."
                exit 1
            fi

            # Previous sudo Git commands may have left root-owned files
            # such as .git/FETCH_HEAD. Git itself must run unprivileged.
            if ! sudo chown -R "$REPO_OWNER:$REPO_GROUP" "$REPO_DIR/.git"; then
                log_message "$RED" "Failed to repair Git repository permissions."
                exit 1
            fi

            if ! git fetch --force --prune origin --tags; then
                log_message "$RED" "Failed to fetch GitHub updates. Aborting."
                exit 1
            fi

            # HEAD must be equal to or behind the requested release.
            if ! git merge-base --is-ancestor HEAD "${LATEST_TAG}"; then
                log_message "$RED" "Local main is not behind $LATEST_TAG."
                log_message "$RED" "Refusing to overwrite or downgrade local code."
                exit 1
            fi

            if ! git merge --ff-only "${LATEST_TAG}"; then
                log_message "$RED" "Could not fast-forward main to $LATEST_TAG."
                exit 1
            fi

            if ! sync_installer_runtime; then
                log_message "$RED" "Runtime synchronization failed."
                log_message "$YELLOW" "Restoring repository to $OLD_HEAD..."
                git reset --hard "$OLD_HEAD" >/dev/null 2>&1 || true
                exit 1
            fi

            echo "VERSION=${LATEST_TAG}" | sudo tee /etc/yiimpoolversion.conf >/dev/null
            VERSION="${LATEST_TAG}"

            log_message "$GREEN" "Version updated to $LATEST_TAG"

            if ! verify_upgrade; then
                log_message "$RED" "Post-upgrade service check failed. Please review service status."
                exit 1
            fi

            echo
            log_message "$GREEN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            log_message "$GREEN" "  SQSYIIMP upgrade complete!"
            log_message "$GREEN" "  New version: $LATEST_TAG"
            log_message "$GREEN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            log_message "$YELLOW" "  Run 'yiimpool' to return to the management menu."
            echo
            ;;

        "stratum")
            log_message "$YELLOW" "Running stratum-only upgrade..."
            echo

            if ! upgrade_stratum; then
                log_message "$RED" "Stratum upgrade failed. Check the output above for details."
                exit 1
            fi

            if ! verify_upgrade; then
                log_message "$RED" "Post-upgrade service check failed. Please review service status."
                exit 1
            fi

            echo
            log_message "$GREEN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            log_message "$GREEN" "  Stratum upgrade complete!"
            log_message "$GREEN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            log_message "$YELLOW" "  Run 'yiimpool' to return to the management menu."
            echo
            ;;
    esac
}

main "$@"
