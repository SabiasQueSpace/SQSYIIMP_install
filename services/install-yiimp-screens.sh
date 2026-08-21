#!/usr/bin/env bash

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load SQSYIIMP installation configuration when available.
if [[ -r /etc/yiimpool.conf ]]; then
    # shellcheck disable=SC1091
    source /etc/yiimpool.conf
fi

STORAGE_USER="${STORAGE_USER:-crypto-data}"
STORAGE_GROUP="${STORAGE_GROUP:-${STORAGE_USER}}"
STORAGE_ROOT="${STORAGE_ROOT:-/home/${STORAGE_USER}}"

YIIMP_USER="${STORAGE_USER}"
YIIMP_HOME="${STORAGE_ROOT}"
YIIMP_SITE="${STORAGE_ROOT}/yiimp/site"

echo
echo "=============================================="
echo " SQSYIIMP YiiMP Screen Service Installer"
echo "=============================================="
echo

if ! id "${STORAGE_USER}" >/dev/null 2>&1; then
    echo "ERROR: service user ${STORAGE_USER} does not exist"
    exit 1
fi

if ! getent group "${STORAGE_GROUP}" >/dev/null 2>&1; then
    echo "ERROR: service group ${STORAGE_GROUP} does not exist"
    exit 1
fi

for file in \
    "${YIIMP_SITE}/crons/loop2.sh" \
    "${YIIMP_SITE}/crons/blocks.sh" \
    "${YIIMP_SITE}/crons/main.sh"
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

# Runtime configuration shared by systemd and interactive tools.
TMP_RUNTIME="$(mktemp)"
cat > "${TMP_RUNTIME}" <<EOF
YIIMP_USER=${YIIMP_USER}
YIIMP_HOME=${YIIMP_HOME}
YIIMP_SITE=${YIIMP_SITE}
EOF

sudo install \
    -o root \
    -g root \
    -m 644 \
    "${TMP_RUNTIME}" \
    /etc/default/sqsyiimp

rm -f "${TMP_RUNTIME}"

# Render systemd template with the configured service account.
TMP_SERVICE="$(mktemp)"

sed \
    -e "s|__STORAGE_USER__|${STORAGE_USER}|g" \
    -e "s|__STORAGE_GROUP__|${STORAGE_GROUP}|g" \
    "${REPO_DIR}/yiimp-screens.service" \
    > "${TMP_SERVICE}"

sudo install \
    -o root \
    -g root \
    -m 644 \
    "${TMP_SERVICE}" \
    /etc/systemd/system/yiimp-screens.service

rm -f "${TMP_SERVICE}"

sudo install \
    -d \
    -o "${STORAGE_USER}" \
    -g "${STORAGE_GROUP}" \
    -m 755 \
    "${YIIMP_SITE}/log"

sudo touch "${YIIMP_SITE}/log/debug.log"

sudo chown \
    "${STORAGE_USER}:${STORAGE_GROUP}" \
    "${YIIMP_SITE}/log/debug.log"

# ------------------------------------------------------------
# Remove obsolete root boot launcher
# ------------------------------------------------------------

if sudo crontab -l >/dev/null 2>&1; then

    TMP_CRON="$(mktemp)"

    sudo crontab -l 2>/dev/null |
        grep -vF "${STORAGE_ROOT}/yiimp/starts/screens.start.sh" |
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
