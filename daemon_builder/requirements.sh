#!/usr/bin/env bash

#
# Author: SabiasQue.Space
# Date: 2023-01-12
#
# Description: This install all requirements for DaemonBuilder.
#

source /etc/functions.sh
source /etc/yiimpool.conf
source $STORAGE_ROOT/yiimp/.yiimp.conf

set -eu -o pipefail

function print_error {
	read line file <<<$(caller)
	echo "An error occurred in line $line of file $file:" >&2
	sed "${line}q;d" "$file" >&2
}
trap print_error ERR

term_art

print_header "DaemonBuilder Requirements Setup"

print_status "Setting up DaemonBuilder utilities..."
cd $HOME/sqsyiimp/daemon_builder
hide_output sudo cp -r $HOME/sqsyiimp/daemon_builder/utils/screen-scrypt-daemonbuilder.sh /etc/
hide_output sudo chmod +x /etc/screen-scrypt-daemonbuilder.sh
print_success "DaemonBuilder utilities configured"

print_header "Installing All Required Packages"

print_status "Updating package lists..."
hide_output sudo apt-get update
hide_output sudo apt-get -y upgrade

print_status "Installing all required packages..."
DAEMONBUILDER_PACKAGES=(
    "build-essential"
    "cmake"
    "ccache"
    "pkg-config"
    "autotools-dev"
    "automake"
    "libtool"

    "p7zip-full"
    "zlib1g-dev"

    "libssl-dev"
    "libevent-dev"
    "libseccomp-dev"
    "libcap-dev"
    "bsdextrautils"

    "libboost-all-dev"
    "libboost-chrono-dev"
    "libboost-date-time-dev"
    "libboost-filesystem-dev"
    "libboost-locale-dev"
    "libboost-program-options-dev"
    "libboost-regex-dev"
    "libboost-serialization-dev"
    "libboost-system-dev"
    "libboost-thread-dev"

    "libleveldb-dev"
    "libdb5.3-dev"
    "libdb5.3++-dev"
    "libdb-dev"
    "libsqlite3-dev"

    "libzmq5"
    "libzmq3-dev"
    "libminiupnpc-dev"
    "libnatpmp-dev"
    "libunbound-dev"
    "libpgm-dev"

    "qtbase5-dev"
    "libqt5webkit5-dev"
    "qttools5-dev"
    "qttools5-dev-tools"
    "qtwayland5"

    "libprotobuf-dev"
    "protobuf-compiler"
    "bison"
    "libgmp-dev"
    "libsodium-dev"
    "libunwind-dev"
    "liblzma-dev"
    "libreadline-dev"
    "libldns-dev"
    "libexpat1-dev"
    "libhidapi-dev"
    "libusb-1.0-0-dev"
    "libudev-dev"

    "doxygen"
    "graphviz"

    "libcanberra-gtk-module"
    "libqrencode-dev"
    "default-libmysqlclient-dev"
    "libnghttp2-dev"
    "librtmp-dev"
    "libssh2-1-dev"
    "libldap-dev"
    "libidn-dev"
    "libpsl-dev"
    "systemtap-sdt-dev"

)

if is_ubuntu_noble; then
    enable_ubuntu_universe
fi

apt_install_required "${DAEMONBUILDER_PACKAGES[@]}"

print_success "All packages installed successfully"

print_header "Installation Summary"
print_info "Core Development Tools: Installed"
print_info "Database Dependencies: Configured"
print_info "System Libraries: Complete"
print_info "Build Essentials: Ready"
print_success "DaemonBuilder requirements installation completed"

print_divider

set +eu +o pipefail
cd $HOME/sqsyiimp/daemon_builder
source $HOME/sqsyiimp/daemon_builder/berkeley.sh
