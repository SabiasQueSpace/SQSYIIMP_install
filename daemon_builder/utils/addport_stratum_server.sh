#!/usr/bin/env bash

############################################################
# Compatibility wrapper for the remote Stratum port manager
# SabiasQue.Space
############################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/remote_stratum_port_manager.sh"

if [ ! -x "$TARGET" ]; then
    echo "ERROR: Remote Stratum port manager not found: $TARGET" >&2
    exit 127
fi

exec "$TARGET" "$@"
