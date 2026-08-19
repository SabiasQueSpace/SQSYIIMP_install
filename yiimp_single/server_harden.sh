#!/usr/bin/env bash

#####################################################
# Source various web sources:
# https://www.linuxbabe.com/ubuntu/enable-google-tcp-bbr-ubuntu
# https://www.cyberciti.biz/faq/linux-tcp-tuning/
# SQSYIIMP - SabiasQue.Space
#####################################################

source /etc/functions.sh
source /etc/yiimpool.conf
source /etc/yiimpoolversion.conf

SYSCTL_CONF="/etc/sysctl.d/99-yiimpool.conf"

print_header "Server Performance Optimization"

# Ubuntu 22.04+ and Debian 11+ ship a kernel (>=5.15 / >=6.1) that
# already includes TCP BBR natively — no HWE package is needed.
print_status "Kernel already supports BBR — skipping HWE package install"

# Load the BBR kernel module now so the sysctl write below succeeds
# immediately. This is a no-op if BBR is already built-in or loaded.
sudo modprobe tcp_bbr 2>/dev/null || true

print_header "Network Stack Optimization"

# Write all sysctl tuning to a dedicated drop-in file rather than
# appending to /etc/sysctl.conf. Benefits:
#   - Idempotent: re-running the script overwrites the same file
#   - Isolated: our settings do not mix with OS-managed sysctl.conf
#   - Upgrade-safe: OS updates to sysctl.conf do not touch our file
print_status "Writing network performance tuning to ${SYSCTL_CONF}..."
sudo tee "${SYSCTL_CONF}" >/dev/null <<'SYSCTL'
# SQSYIIMP — network performance tuning
# Sources:
#   https://www.linuxbabe.com/ubuntu/enable-google-tcp-bbr-ubuntu
#   https://www.cyberciti.biz/faq/linux-tcp-tuning/

# BBR congestion control
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Network buffer sizes
net.core.wmem_max = 12582912
net.core.rmem_max = 12582912
net.ipv4.tcp_rmem = 10240 87380 12582912
net.ipv4.tcp_wmem = 10240 87380 12582912

# TCP performance parameters
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_no_metrics_save = 1
net.core.netdev_max_backlog = 5000
SYSCTL

# Apply the new settings immediately — no reboot required
print_status "Applying sysctl settings..."
hide_output sudo sysctl --system

print_success "Server performance optimization completed successfully"
