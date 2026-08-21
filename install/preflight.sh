#!/usr/bin/env bash

##################################################################################
# This is the pre-flight check script for configuring the system.                #
# Source https://mailinabox.email/ https://github.com/mail-in-a-box/mailinabox   #
# SQSYIIMP - SabiasQue.Space
##################################################################################

# Source functions and definitions
source /etc/functions.sh

print_header "Pre-flight checks"
print_info "Verifying OS version, memory, swap, and CPU architecture"

# Identify OS using /etc/os-release so Ubuntu point releases such as 24.04.4
# are handled as Ubuntu 24.04 (Noble) without fragile string matching.
detect_os_compat

if [ "$OS_ID" = "ubuntu" ]; then
    case "$OS_VERSION_ID" in
        22.04)
            DISTRO=22
            ;;
        24.04)
            if [ "$OS_CODENAME" != "noble" ]; then
                print_error "Ubuntu 24.04 must report codename noble (detected: $OS_CODENAME)"
                exit 1
            fi
            DISTRO=24
            print_success "Detected ${OS_PRETTY_NAME:-Ubuntu 24.04 LTS} (Noble)"
            ;;
        *)
            print_error "Unsupported Ubuntu release. Supported LTS releases: 22.04 and 24.04.x (including 24.04.4)."
            exit 1
            ;;
    esac
elif [ "$OS_ID" = "debian" ]; then
    case "$OS_VERSION_ID" in
        11) DISTRO=11 ;;
        12) DISTRO=12 ;;
        13) DISTRO=13 ;;
        *)
            print_error "Unsupported Debian release (need 11, 12, or 13)."
            exit 1
            ;;
    esac
else
    print_error "Unsupported operating system: ${OS_PRETTY_NAME:-$OS_ID $OS_VERSION_ID}"
    exit 1
fi

export DISTRO

# Set permissions
sudo chmod g-w /etc /etc/default /usr

# Check if swap is needed and allocate if necessary
SWAP_MOUNTED=$(cat /proc/swaps | tail -n+2)
SWAP_IN_FSTAB=$(grep "swap" /etc/fstab)
ROOT_IS_BTRFS=$(grep "\/ .*btrfs" /proc/mounts)
TOTAL_PHYSICAL_MEM=$(head -n 1 /proc/meminfo | awk '{print $2}')
AVAILABLE_DISK_SPACE=$(df / --output=avail | tail -n 1)

if [ -z "$SWAP_MOUNTED" ] && [ -z "$SWAP_IN_FSTAB" ] && [ ! -e /swapfile ] && [ -z "$ROOT_IS_BTRFS" ] && [ $TOTAL_PHYSICAL_MEM -lt 1536000 ] && [ $AVAILABLE_DISK_SPACE -gt 5242880 ]; then
    print_warning "Low RAM detected; creating a 3G swap file"

    # Allocate and activate the swap file
    sudo fallocate -l 3G /swapfile
    if [ -e /swapfile ]; then
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
        echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf
        echo "/swapfile  none swap sw 0  0" | sudo tee -a /etc/fstab
        print_success "Swap file created and enabled"
    else
        print_error "Swap allocation failed (fallocate /swapfile)"
    fi
fi

# Check architecture
ARCHITECTURE=$(uname -m)
if [ "$ARCHITECTURE" != "x86_64" ]; then
    if [ -z "$ARM" ]; then
        print_error "SQSYIIMP installer requires x86_64 (detected: $ARCHITECTURE)"
        exit 1
    fi
fi

# Set storage/service defaults if not already configured.
STORAGE_USER="${STORAGE_USER:-${DEFAULT_STORAGE_USER:-crypto-data}}"
STORAGE_GROUP="${STORAGE_GROUP:-${DEFAULT_STORAGE_GROUP:-${STORAGE_USER}}}"
STORAGE_ROOT="${STORAGE_ROOT:-${DEFAULT_STORAGE_ROOT:-/home/${STORAGE_USER}}}"

export STORAGE_USER
export STORAGE_GROUP
export STORAGE_ROOT

print_success "Pre-flight checks passed"