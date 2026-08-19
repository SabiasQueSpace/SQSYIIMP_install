#!/usr/bin/env bash

#
# MegaHashPool / SQSYIIMP
# DaemonBuilder main menu
#
# Author: SabiasQue.Space
#

source /etc/daemonbuilder.sh
source "$STORAGE_ROOT/daemon_builder/conf/info.sh"

# SQSYIIMP version must come from the installer version file.
# conf/info.sh has its own VERSION variable and must not overwrite
# the SQSYIIMP release shown by this menu.
SQSYIIMP_VERSION="$(
    awk -F= '$1 == "VERSION" {
        gsub(/[[:space:]\"\047]/, "", $2)
        print $2
        exit
    }' /etc/yiimpoolversion.conf 2>/dev/null
)"

cd "$STORAGE_ROOT/daemon_builder" || exit 1


# ============================================================
# SQSYIIMP VERSION INFORMATION
# ============================================================

CURRENT_USER="${SUDO_USER:-$USER}"

USER_HOME="$(getent passwd "$CURRENT_USER" 2>/dev/null | cut -d: -f6)"

if [[ -z "$USER_HOME" ]]; then
    USER_HOME="$HOME"
fi

REPO_DIR="${SQSYIIMP_REPO_DIR:-${USER_HOME}/sqsyiimp}"

LOCAL_BUILD="unknown"
LOCAL_BRANCH=""
LOCAL_HASH=""
LOCAL_TAG=""

if [[ -d "${REPO_DIR}/.git" ]]; then

    LOCAL_BRANCH="$(
        git -C "$REPO_DIR" branch --show-current 2>/dev/null
    )"

    LOCAL_HASH="$(
        git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null
    )"

    LOCAL_TAG="$(
        git -C "$REPO_DIR" describe --tags --exact-match HEAD 2>/dev/null || true
    )"

    if [[ -n "$LOCAL_TAG" ]]; then
        LOCAL_BUILD="$LOCAL_TAG"
    elif [[ -n "$LOCAL_BRANCH" && -n "$LOCAL_HASH" ]]; then
        LOCAL_BUILD="${LOCAL_BRANCH}@${LOCAL_HASH}"
    elif [[ -n "$LOCAL_HASH" ]]; then
        LOCAL_BUILD="$LOCAL_HASH"
    fi
fi


# ============================================================
# NON-BLOCKING RELEASE CHECK
#
# IMPORTANT:
# Never use read y/n here.
# Never block dialog startup because GitHub is unavailable.
# ============================================================

LATESTVER=""

# SQSYIIMP public version check.
# Uses public Git tags; no SSH alias, GitHub Release, jq or
# authentication is required.
if command -v git >/dev/null 2>&1; then
    LATESTVER="$(
        git ls-remote \
            --tags \
            --refs \
            https://github.com/SabiasQueSpace/SQSYIIMP_install.git \
            'v*' 2>/dev/null |
        awk -F/ '{print $3}' |
        sort -V |
        tail -n 1
    )"
fi


# ============================================================
# MENU INFORMATION
# ============================================================

MENU_INFO="Choose an option.

Installed version: ${SQSYIIMP_VERSION:-v1.0.0}
Local build: ${LOCAL_BUILD}"

if [[ -n "$LATESTVER" ]]; then
    MENU_INFO="${MENU_INFO}
Latest release: ${LATESTVER}"
else
    MENU_INFO="${MENU_INFO}
Latest release: unavailable"
fi


# ============================================================
# MAIN MENU
# ============================================================

UPDATE_MENU_LABEL="Version / Update Information"

if sqsyiimp_version_is_newer     "${SQSYIIMP_VERSION:-}"     "${LATESTVER:-}"
then
    UPDATE_MENU_LABEL="Update SQSYIIMP ${SQSYIIMP_VERSION} -> ${LATESTVER}"
fi

RESULT=$(
    dialog \
        --stdout \
        --backtitle "MegaHashPool - SQSYIIMP" \
        --title "DaemonBuilder ${SQSYIIMP_VERSION:-v1.0.0}" \
        --menu "$MENU_INFO" \
        22 72 8 \
        ' ' "═══════════  Daemon Builder ═══════════" \
        1 "Build Coin Daemon From Source Code" \
        2 "Update Coin Daemon From Source Code" \
        ' ' "───────────────────────────────────────" \
        3 "$UPDATE_MENU_LABEL" \
        4 "Exit DaemonBuilder"
)

DIALOG_RC=$?


# ESC / Cancel
if [[ "$DIALOG_RC" -ne 0 ]]; then
    clear
    exit 0
fi


case "$RESULT" in

    1)
        clear
        cd "$STORAGE_ROOT/daemon_builder" || exit 1
        source menu1.sh
        ;;

    2)
        clear
        cd "$STORAGE_ROOT/daemon_builder" || exit 1
        source menu2.sh
        ;;

    3)
        UPDATE_TEXT="SQSYIIMP / DaemonBuilder

Installed version:
${SQSYIIMP_VERSION}

Local build:
${LOCAL_BUILD}

Latest published release:
${LATESTVER:-unavailable}"

        if sqsyiimp_version_is_newer \
            "${SQSYIIMP_VERSION:-}" \
            "${LATESTVER:-}"
        then
            UPDATE_TEXT="${UPDATE_TEXT}

A newer SQSYIIMP version is available.

Update:
${SQSYIIMP_VERSION}  ->  ${LATESTVER}

Do you want to start the SQSYIIMP updater now?"

            if dialog \
                --backtitle "MegaHashPool - SQSYIIMP" \
                --title "SQSYIIMP Update Available" \
                --yesno "$UPDATE_TEXT" \
                23 76
            then
                clear

                if ! sqsyiimp_run_updater; then
                    dialog \
                        --backtitle "MegaHashPool - SQSYIIMP" \
                        --title "SQSYIIMP Update" \
                        --msgbox "The SQSYIIMP updater did not complete successfully." \
                        9 64
                fi
            fi
        else
            UPDATE_TEXT="${UPDATE_TEXT}

SQSYIIMP is up to date."

            dialog \
                --backtitle "MegaHashPool - SQSYIIMP" \
                --title "Version / Update Information" \
                --msgbox "$UPDATE_TEXT" \
                19 76
        fi

        exec bash "$STORAGE_ROOT/daemon_builder/start.sh"
        ;;

    4)
        clear
        echo -e "$CYAN ------------------------------------------------------------------------------- $NC"
        echo -e "$YELLOW You have chosen to exit the Daemon Builder.$NC"
        echo -e "$YELLOW Type: $BLUE daemonbuilder $YELLOW anytime to start the menu again.$NC"
        echo -e "$CYAN ------------------------------------------------------------------------------- $NC"
        exit 0
        ;;

esac
