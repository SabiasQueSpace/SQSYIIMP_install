#!/usr/bin/env bash

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo
echo "=============================================="
echo " SQSYIIMP YiiMP Screen Service Installer"
echo "=============================================="
echo

if ! id crypto-data >/dev/null 2>&1; then
    echo "ERROR: user crypto-data does not exist"
    exit 1
fi

for file in \
    /home/crypto-data/yiimp/site/crons/loop2.sh \
    /home/crypto-data/yiimp/site/crons/blocks.sh \
    /home/crypto-data/yiimp/site/crons/main.sh
do
    if [[ ! -f "$file" ]]; then
        echo "ERROR: required file missing:"
        echo "$file"
        exit 1
    fi
done

sudo install \
    -o root \
    -g root \
    -m 755 \
    "${REPO_DIR}/yiimp-screens.sh" \
    /usr/local/bin/yiimp-screens

sudo install \
    -o root \
    -g root \
    -m 644 \
    "${REPO_DIR}/yiimp-screens.service" \
    /etc/systemd/system/yiimp-screens.service

sudo install \
    -d \
    -o crypto-data \
    -g crypto-data \
    -m 755 \
    /home/crypto-data/yiimp/site/log

sudo touch /home/crypto-data/yiimp/site/log/debug.log

sudo chown \
    crypto-data:crypto-data \
    /home/crypto-data/yiimp/site/log/debug.log

# ------------------------------------------------------------
# Remove obsolete root boot launcher
# ------------------------------------------------------------

if sudo crontab -l >/dev/null 2>&1; then

    TMP_CRON="$(mktemp)"

    sudo crontab -l 2>/dev/null |
        grep -vF '/home/crypto-data/yiimp/starts/screens.start.sh' \
        > "${TMP_CRON}" || true

    sudo crontab "${TMP_CRON}"

    rm -f "${TMP_CRON}"

    echo "SUCCESS: legacy root screen @reboot removed"
fi

# ------------------------------------------------------------
# SQSYIIMP legacy command compatibility
# ------------------------------------------------------------

echo
echo "Installing legacy Screen compatibility..."

sudo install \
    -o root \
    -g root \
    -m 755 \
    "${REPO_DIR}/screens-compat" \
    /usr/local/bin/screens

sudo install \
    -o root \
    -g root \
    -m 644 \
    "${REPO_DIR}/sqsyiimp-screen-compat.sh" \
    /etc/profile.d/sqsyiimp-screen-compat.sh

echo "SUCCESS: Legacy Screen compatibility installed"
echo "         screen -r main"
echo "         screen -r loop2"
echo "         screen -r blocks"
echo "         screen -r debug"
echo "         screens status"

sudo systemctl daemon-reload

echo
echo "SUCCESS: SQSYIIMP YiiMP screen manager installed"
echo
echo "Command:"
echo "  yiimp-screens status"
echo
