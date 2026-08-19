#!/usr/bin/env bash

##################################################################################
# This is the entry point for configuring the system.                            #
# Source https://mailinabox.email/ https://github.com/mail-in-a-box/mailinabox   #
# SQSYIIMP - SabiasQue.Space
##################################################################################


# SQSYIIMP uses ~/sqsyiimp as its canonical repository path. If this entry
# point is launched directly from an older checkout, create a temporary
# compatibility link so the remaining scripts can use the canonical path.
if [ ! -e "$HOME/sqsyiimp" ]; then
    for legacy_repo in "$HOME/SQSYIIMP"; do
        if [ -d "$legacy_repo" ]; then
            ln -s "$legacy_repo" "$HOME/sqsyiimp" 2>/dev/null || true
            break
        fi
    done
fi

# Include functions for color output and other utilities.
if [ -r /etc/functions.sh ]; then

    source /etc/functions.sh
elif [ -r "$HOME/sqsyiimp/install/functions.sh" ]; then

    source "$HOME/sqsyiimp/install/functions.sh"
else
    echo "SQSYIIMP: functions.sh not found (install SQSYIIMP under \$HOME or run from a configured system)." >&2
    exit 1
fi

# Recall the last settings used if we're running this a second time.
if [ -f /etc/yiimpool.conf ]; then
    print_status "Loading previous configuration from /etc/yiimpool.conf"
    # Load the old .conf file to get existing configuration options loaded
    # into variables with a DEFAULT_ prefix.
    cat /etc/yiimpool.conf | sed s/^/DEFAULT_/ >/tmp/yiimpool.prev.conf
    source /tmp/yiimpool.prev.conf
    print_success "Previous configuration loaded"
    print_status "Loading version information"
    source /etc/yiimpoolversion.conf
    print_success "Version information loaded"
    rm -f /tmp/yiimpool.prev.conf
    print_info "Removed temporary yiimpool.prev.conf"
else
    FIRST_TIME_SETUP=1
    print_warning "First-time setup detected (no /etc/yiimpool.conf yet)"
fi

if [[ "$FIRST_TIME_SETUP" == "1" ]]; then
    clear
    cd "$HOME/sqsyiimp/install"

    source functions.sh

    print_header "First-time SQSYIIMP setup"
    print_status "Installing helper scripts to /etc and /usr/bin"
    # Copy functions to /etc
    sudo cp -r functions.sh /etc/
    sudo cp -r editconf.py /usr/bin
    sudo chmod +x /usr/bin/editconf.py
    print_success "functions.sh and editconf.py installed"

    # Check system setup: validate a supported LTS release (Ubuntu 22.04 or
    # Ubuntu 24.04.x, including 24.04.4) and minimum host requirements.
    # If not, this shows an error and exits.
    print_header "Pre-flight system checks"
    source preflight.sh

    # Ensure Python reads/writes files in UTF-8.
    if ! locale -a | grep en_US.utf8 >/dev/null; then
        print_status "Generating en_US.UTF-8 locale"
        hide_output locale-gen en_US.UTF-8
    fi

    export LANGUAGE=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    export LANG=en_US.UTF-8
    export LC_TYPE=en_US.UTF-8
    print_success "Locale set to en_US.UTF-8"

    # Fix so line drawing characters are shown correctly in Putty on Windows. See #744.
    export NCURSES_NO_UTF8_ACS=1
    print_info "NCURSES_NO_UTF8_ACS=1 (better line drawing in PuTTY)"

    print_header "Bootstrap packages"
    print_status "Preparing APT repositories and bootstrap tools"
    if [ "$OS_ID" = "ubuntu" ]; then
        enable_ubuntu_universe
    else
        hide_output sudo apt-get update
    fi
    apt_install_required dialog python3 python3-pip acl nano git ca-certificates curl
    apt_install_optional figlet lolcat apt-transport-https
    print_success "Bootstrap packages installed"

    # Are we running as root?
    if [[ $EUID -ne 0 ]]; then
        print_status "Non-root session: showing welcome dialog"
        # Welcome
        message_box "SQSYIIMP Installer $VERSION" \
        "${YELLOW}Hello and thanks for using the SQSYIIMP Installer!${NC}
        \n\n${GREEN}Installation for the most part is fully automated. In most cases any user responses that are needed are asked prior to the installation.${NC}
        \n\n${RED}NOTE: Use a brand new Ubuntu 22.04 LTS or Ubuntu 24.04.x LTS installation. Ubuntu 24.04.4 is explicitly supported.${NC}"
        source existing_user.sh
        exit
    else
        print_status "Running as root: creating unprivileged install user next"
        source create_user.sh
        exit
    fi
    cd ~

else
    clear
    print_header "SQSYIIMP installer (returning session)"
    print_status "Reloading configuration from /etc/yiimpool.conf"

    # Ensure Python reads/writes files in UTF-8.
    if ! locale -a | grep en_US.utf8 >/dev/null; then
        print_status "Generating en_US.UTF-8 locale"
        hide_output locale-gen en_US.UTF-8
    fi

    export LANGUAGE=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    export LANG=en_US.UTF-8
    export LC_TYPE=en_US.UTF-8
    print_success "Locale set to en_US.UTF-8"

    export NCURSES_NO_UTF8_ACS=1
    print_info "NCURSES_NO_UTF8_ACS=1 (better line drawing in PuTTY)"

    print_status "Refreshing /etc/functions.sh from the repository copy"
    # Always refresh /etc/functions.sh so it stays in sync with the repo
    sudo cp -f "$HOME/sqsyiimp/install/functions.sh" /etc/functions.sh
    source /etc/functions.sh
    source /etc/yiimpool.conf
    print_success "Functions and yiimpool.conf loaded"

    print_header "Main menu"
    print_info "Choose Install or Manage & Upgrade options"
    cd "$HOME/sqsyiimp/install"
    source menu.sh
    cd ~
fi
