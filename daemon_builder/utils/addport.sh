#!/usr/bin/env bash

############################################################
# Compatibility wrapper for the Stratum Port Manager
# SabiasQue.Space
############################################################

if command -v addport >/dev/null 2>&1 && [ "$(command -v addport)" != "$0" ]; then
    exec addport "$@"
fi

if [ -x "$HOME/sqsyiimp/stratum_manager/addport.sh" ]; then
    exec "$HOME/sqsyiimp/stratum_manager/addport.sh" "$@"
fi

if [ -x "$HOME/sqsyiimp/stratum_tools/stratum-port-manager.sh" ]; then
    exec "$HOME/sqsyiimp/stratum_tools/stratum-port-manager.sh" "$@"
fi

if [ -n "${STORAGE_ROOT:-}" ] && [ -x "$STORAGE_ROOT/daemon_builder/addport.sh" ]; then
    exec "$STORAGE_ROOT/daemon_builder/addport.sh" "$@"
fi

if command -v sqs-stratum-port >/dev/null 2>&1; then
    exec sqs-stratum-port "$@"
fi

echo "ERROR: Stratum Port Manager is not installed." >&2
exit 127
