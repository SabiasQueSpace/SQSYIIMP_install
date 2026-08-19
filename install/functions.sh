#!/bin/bash

##############################################
#											 #
# SQSYIIMP - SabiasQue.Space
# SQSYIIMP - SabiasQue.Space
# 											 #
##############################################

source /etc/yiimpoolversion.conf

ESC_SEQ="\x1b["
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[0;36m'
NC='\033[0m'


# Return the pool identity used for Stratum coinbaseextra.
# Primary source: YAAMP_SITE_NAME from /etc/yiimp/serverconfig.php.
# Fallback: DomainName from the installer configuration.
function get_pool_coinbase_tag() {
    local server_config="${1:-/etc/yiimp/serverconfig.php}"
    local pool_name=""

    if command -v php >/dev/null 2>&1 && [ -r "$server_config" ]; then
        pool_name="$(php -r '
            $config = $argv[1];
            require $config;
            if (defined("YAAMP_SITE_NAME")) {
                echo YAAMP_SITE_NAME;
            } elseif (defined("YIIMP_SITE_NAME")) {
                echo YIIMP_SITE_NAME;
            }
        ' "$server_config" 2>/dev/null || true)"
    fi

    if [ -z "$pool_name" ] && [ -n "${DomainName:-}" ]; then
        pool_name="$DomainName"
    fi

    if [ -z "$pool_name" ]; then
        echo "Unable to determine the pool name for coinbaseextra." >&2
        return 1
    fi

    if [ "${#pool_name}" -ge 32 ]; then
        echo "Pool name is too long for coinbaseextra (${#pool_name} characters; maximum 31)." >&2
        return 1
    fi

    if ! LC_ALL=C printf '%s' "$pool_name" | grep -qE '^[A-Za-z0-9._ -]+$'; then
        echo "Pool name contains unsupported characters for coinbaseextra: $pool_name" >&2
        return 1
    fi

    printf '%s' "$pool_name"
}

# Ensure every Stratum *.conf contains exactly one coinbaseextra entry in
# the [STRATUM] section. Existing values are replaced with the YiiMP site name.
function apply_coinbaseextra_to_configs() {
    local config_dir="$1"
    local pool_name="$2"

    if [ ! -d "$config_dir" ]; then
        echo "Stratum config directory not found: $config_dir" >&2
        return 1
    fi

    if [ -z "$pool_name" ]; then
        echo "Pool name is empty; refusing to update coinbaseextra." >&2
        return 1
    fi

    if [ "${#pool_name}" -ge 32 ]; then
        echo "Pool name is too long for coinbaseextra (${#pool_name} characters; maximum 31)." >&2
        return 1
    fi

    if ! LC_ALL=C printf '%s' "$pool_name" | grep -qE '^[A-Za-z0-9._ -]+$'; then
        echo "Pool name contains unsupported characters for coinbaseextra: $pool_name" >&2
        return 1
    fi

    sudo python3 - "$config_dir" "$pool_name" <<'PY'
from pathlib import Path
import re
import sys

config_dir = Path(sys.argv[1])
pool_name = sys.argv[2]
files = sorted(config_dir.glob("*.conf"))

if not files:
    raise SystemExit(f"No .conf files found in {config_dir}")

prepared = []
for path in files:
    text = path.read_text()
    newline = "\r\n" if "\r\n" in text else "\n"
    had_final_newline = text.endswith(("\n", "\r\n"))
    lines = text.splitlines()

    lines = [
        line for line in lines
        if not re.match(r"^\s*coinbaseextra\s*=", line, flags=re.IGNORECASE)
    ]

    insert_at = None
    for index, line in enumerate(lines):
        if re.match(r"^\s*\[STRATUM\]\s*$", line, flags=re.IGNORECASE):
            insert_at = index + 1
            break

    if insert_at is None:
        raise SystemExit(f"No [STRATUM] section found in {path}")

    lines.insert(insert_at, f"coinbaseextra = {pool_name}")
    output = newline.join(lines)
    if had_final_newline:
        output += newline

    prepared.append((path, output))

# Validate every configuration before changing any file. This prevents a
# malformed later file from leaving earlier files only partially updated.
for path, output in prepared:
    path.write_text(output)

print(f"coinbaseextra synchronized in {len(prepared)} Stratum config file(s): {pool_name}")
PY
}

function spinner {
    local pid=$!
    local delay=0.35
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# terminal art end screen.

function install_end_message() {

  clear

  # Define color codes (avoid hardcoding in the function)
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BOLD_YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  BOLD_CYAN='\033[1;36m'
  NC='\033[0m'  # Reset color

  echo "Yiimp Installation Complete!"
  echo

  figlet -f slant -w 100 "Success"

  echo -e "${BOLD_GREEN}**Yiimp Version:**${NC} $VERSION"
  echo

  echo -e "${BOLD_CYAN}**Database Information:**${NC}"
  echo "  - Login credentials are saved securely in ~/.my.cnf"
  echo

  echo -e "${BOLD_CYAN}**Pool and Admin Panel Access:**${NC}"
  echo "  - Pool: http://$server_name"
  echo "  - Admin Panel: http://$server_name/site/AdminPanel"
  echo "  - phpMyAdmin: http://$server_name/phpmyadmin"
  echo

  echo -e "${BOLD_CYAN}**Customization:**${NC}"
  echo "  - To modify the admin panel URL (currently set to '$admin_panel'):"
  echo "    - Edit ${BOLD_YELLOW}/var/web/yaamp/modules/site/SiteController.php${NC}"
  echo "    - Update line 11 with your desired URL"
  echo

  echo -e "${BOLD_CYAN}**Security Reminders:**${NC}"
  echo "  - Update public keys and wallet addresses in ${BOLD_YELLOW}/var/web/serverconfig.php${NC}"
  echo "  - Replace placeholder private keys in ${BOLD_YELLOW}/etc/yiimp/keys.php${NC} with your actual keys"
  echo "    - ${RED}Never share your private keys with anyone!${NC}"
  echo

  echo -e "${BOLD_YELLOW}**Next Steps:**${NC}"
  echo "  1. Reboot your server to finalize the installation process. ( ${RED}reboot${NC} )"
  echo "  2. Secure your installation by following best practices for server security."
  echo

  echo "Thank you for using SQSYIIMP — SabiasQue.Space!"

}


function sqsyiimp_logo() {
  local logo_text="SQSYIIMP"

  if command -v figlet >/dev/null 2>&1; then
    if command -v lolcat >/dev/null 2>&1; then
      figlet -f slant -w 100 "$logo_text" | lolcat -f
    else
      figlet -f slant -w 100 "$logo_text"
    fi
  else
    echo -e "${CYAN}  ███████╗ ██████╗ ███████╗██╗   ██╗██╗██╗███╗   ███╗██████╗ ${NC}"
    echo -e "${CYAN}  ██╔════╝██╔═══██╗██╔════╝╚██╗ ██╔╝██║██║████╗ ████║██╔══██╗${NC}"
    echo -e "${CYAN}  ███████╗██║   ██║███████╗ ╚████╔╝ ██║██║██╔████╔██║██████╔╝${NC}"
    echo -e "${CYAN}  ╚════██║██║▄▄ ██║╚════██║  ╚██╔╝  ██║██║██║╚██╔╝██║██╔═══╝ ${NC}"
    echo -e "${CYAN}  ███████║╚██████╔╝███████║   ██║   ██║██║██║ ╚═╝ ██║██║     ${NC}"
    echo -e "${CYAN}  ╚══════╝ ╚══▀▀═╝ ╚══════╝   ╚═╝   ╚═╝╚═╝╚═╝     ╚═╝╚═╝     ${NC}"
  fi
}

function term_art() {
  clear

  local width
  width=$(tput cols 2>/dev/null || echo 80)
  [ "$width" -gt 96 ] && width=96
  [ "$width" -lt 58 ] && width=58

  sqsyiimp_logo
  echo
  printf '─%.0s' $(seq 1 "$width"); printf '\n'
  echo -e "${CYAN}${BOLD:-\033[1m}  SQSYIIMP Mining Pool Installer${NC}"
  echo -e "${YELLOW}  SabiasQue.Space${NC}"
  echo -e "${CYAN}  Version:${NC} ${GREEN}${VERSION:-unknown}${NC}"
  echo -e "${CYAN}  Workspace:${NC} ${GREEN}$HOME/sqsyiimp${NC}"
  printf '─%.0s' $(seq 1 "$width"); printf '\n'
  echo
  echo -e "  ${GREEN}●${NC} YiiMP web platform"
  echo -e "  ${GREEN}●${NC} Stratum and mining services"
  echo -e "  ${GREEN}●${NC} Database, daemon and server tooling"
  echo
}

function term_yiimpool() {
  term_art
}


function daemonbuiler_files {
        echo -e "$YELLOW Copy => Copy Daemonbuilder files. <= ${NC}"

        local daemonbuilder_source="$HOME/sqsyiimp/daemon_builder/utils"
        local daemonbuilder_target="$STORAGE_ROOT/daemon_builder"

        echo -e "${CYAN}  Source : ${daemonbuilder_source}${NC}"
        echo -e "${CYAN}  Target : ${daemonbuilder_target}${NC}"

        if [[ ! -d "$daemonbuilder_source" ]]; then
                echo -e "${RED}ERROR: DaemonBuilder source directory does not exist:${NC}"
                echo -e "${RED}       $daemonbuilder_source${NC}"
                return 1
        fi

        sudo mkdir -p "$daemonbuilder_target"

        #
        # Canonical install:
        #
        # ~/sqsyiimp/daemon_builder/utils/*
        #              ↓
        # $STORAGE_ROOT/daemon_builder/
        #
        sudo cp -r "$daemonbuilder_source"/. "$daemonbuilder_target"/

        #
        # Validate critical runtime files.
        #
        local required_file

        for required_file in \
                start.sh \
                source.sh \
                upgrade.sh \
                menu.sh \
                menu2.sh \
                menu3.sh
        do
                if [[ ! -f "$daemonbuilder_target/$required_file" ]]; then
                        echo -e "${RED}ERROR: Missing installed DaemonBuilder file:${NC}"
                        echo -e "${RED}       $daemonbuilder_target/$required_file${NC}"
                        return 1
                fi
        done

        #
        # Validate shell syntax before exposing daemonbuilder command.
        #
        if ! bash -n "$daemonbuilder_target/start.sh"; then
                echo -e "${RED}ERROR: Invalid syntax in installed start.sh${NC}"
                return 1
        fi

        if ! bash -n "$daemonbuilder_target/source.sh"; then
                echo -e "${RED}ERROR: Invalid syntax in installed source.sh${NC}"
                return 1
        fi

        if ! bash -n "$daemonbuilder_target/upgrade.sh"; then
                echo -e "${RED}ERROR: Invalid syntax in installed upgrade.sh${NC}"
                return 1
        fi

        #
        # Main command.
        #
        cat <<'EOF' | sudo tee /usr/bin/daemonbuilder >/dev/null
#!/usr/bin/env bash

source /etc/functions.sh
source /etc/yiimpool.conf

cd "$STORAGE_ROOT/daemon_builder" || exit 1
exec bash start.sh
EOF

        sudo chmod 755 /usr/bin/daemonbuilder

        echo
        echo -e "$GREEN => DaemonBuilder files installed successfully${NC}"
        echo -e "$GREEN => Runtime: $daemonbuilder_target${NC}"

        sleep 2
}

# Stop unattended-upgrades / apt-daily and wait until dpkg locks are free so installs do not
# block on "Waiting for cache lock" (common right after boot or during security updates).
function prepare_apt_for_install {
	sudo systemctl stop unattended-upgrades.service 2>/dev/null || true
	sudo systemctl stop apt-daily.service 2>/dev/null || true
	sudo systemctl stop apt-daily-upgrade.service 2>/dev/null || true
	local max_wait=600
	local w=0
	if command -v fuser >/dev/null 2>&1; then
		while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
			|| sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
			sleep 2
			w=$((w + 2))
			if [ "$w" -ge "$max_wait" ]; then
				echo "prepare_apt_for_install: timed out after ${max_wait}s waiting for dpkg lock" >&2
				return 1
			fi
		done
	fi
	return 0
}

function hide_output {
	OUTPUT=$(mktemp)
	$@ &>$OUTPUT &
	local _hpid=$!
	spinner
	wait "$_hpid"
	E=$?
	if [ $E != 0 ]; then
		echo
		echo FAILED: $@
		echo -----------------------------------------
		cat $OUTPUT
		echo -----------------------------------------
		exit $E
	fi

	rm -f $OUTPUT
}

# function hide_output {
	# OUTPUT=$(tempfile)
	# $@ &>$OUTPUT &
	# spinner
	# E=$?
	# if [ $E != 0 ]; then
		# echo
		# echo FAILED: $@
		# echo -----------------------------------------
		# cat $OUTPUT
		# echo -----------------------------------------
		# exit $E
	# fi
#
	# rm -f $OUTPUT
# }


function last_words {
        echo "<-------------------------------------|---------------------------------------->"
        echo
        echo -e "$YELLOW Thank you for using the SQSYIIMP Installer $GREEN $VERSION ${NC}"
        echo
        echo -e "$YELLOW To run the installer again, simply type: $GREEN yiimpool ${NC}"
        echo
        echo -e "$YELLOW SQSYIIMP — SabiasQue.Space ${NC}"
        echo
        exit 0
}

function package_compile_crypto {

    print_header "Cryptocurrency Build Dependencies"
    print_status "Installing distribution-compatible build packages"

    detect_os_compat
    if is_ubuntu_noble; then
        enable_ubuntu_universe
    else
        hide_output sudo apt-get update
    fi

    # Use development metapackages instead of versioned runtime package names.
    # On Ubuntu 24.04 these automatically pull the t64 runtimes (for example
    # libdb5.3t64) and the correct miniupnpc ABI without hardcoding old names.
    apt_install_required \
        software-properties-common build-essential git cmake ccache doxygen graphviz \
        libtool autotools-dev automake pkg-config gettext bison \
        libssl-dev libevent-dev libboost-all-dev zlib1g-dev \
        libseccomp-dev libcap-dev libminiupnpc-dev libzmq3-dev libqrencode-dev \
        libprotobuf-dev protobuf-compiler libgmp-dev libunbound-dev libsodium-dev \
        libunwind-dev liblzma-dev libreadline-dev libldns-dev libexpat1-dev \
        libpgm-dev libhidapi-dev libusb-1.0-0-dev libudev-dev \
        libboost-chrono-dev libboost-date-time-dev libboost-filesystem-dev \
        libboost-locale-dev libboost-program-options-dev libboost-regex-dev \
        libboost-serialization-dev libboost-system-dev libboost-thread-dev \
        default-libmysqlclient-dev libnghttp2-dev libssh2-1-dev libldap-dev \
        libpsl-dev libdb5.3-dev libdb5.3++-dev

    # GUI and coin-specific libraries are optional because not every daemon uses
    # Qt, NAT-PMP, canberra, or the same networking extras.
    apt_install_optional \
        p7zip-full libnatpmp-dev libcanberra-gtk-module librtmp-dev libidn-dev \
        qtbase5-dev libqt5webkit5-dev qttools5-dev qttools5-dev-tools \
        qtwayland5 systemtap-sdt-dev

    print_success "Cryptocurrency build dependencies installed"
    print_info "Legacy Berkeley DB 4.8 is built separately by daemon_builder/berkeley.sh"
}

# Function to check if a package is installed and install it if not
install_if_not_installed() {
  local package="$1"
  if ! command -v "$package" &>/dev/null; then
    echo "Installing $package..."
    hide_output sudo apt install -y "$package"
  else
    echo "$package is already installed."
  fi
}

# Function to check package installation status
function check_package_installed() {
    if ! dpkg -l | grep -q "^ii  $1"; then
        echo "Failed to install package: $1"
        return 1
    fi
}

function apt_get_quiet {
	DEBIAN_FRONTEND=noninteractive hide_output sudo apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" "$@"
}

# Detect the host distribution from /etc/os-release. Ubuntu point releases such
# as 24.04.4 keep VERSION_ID=24.04 and VERSION_CODENAME=noble, so package
# selection must follow the base release/codename rather than the point number.
function detect_os_compat {
    if [ ! -r /etc/os-release ]; then
        print_error "/etc/os-release is missing; unable to detect the operating system"
        return 1
    fi

    local os_id os_version os_codename os_pretty
    os_id=$(awk -F= '$1=="ID" {gsub(/\"/, "", $2); print $2}' /etc/os-release)
    os_version=$(awk -F= '$1=="VERSION_ID" {gsub(/\"/, "", $2); print $2}' /etc/os-release)
    os_codename=$(awk -F= '$1=="VERSION_CODENAME" {gsub(/\"/, "", $2); print $2}' /etc/os-release)
    os_pretty=$(awk -F= '$1=="PRETTY_NAME" {$1=""; sub(/^=/, ""); gsub(/\"/, ""); sub(/^ /, ""); print}' /etc/os-release)

    export OS_ID="$os_id"
    export OS_VERSION_ID="$os_version"
    export OS_CODENAME="$os_codename"
    export OS_PRETTY_NAME="$os_pretty"

    case "$OS_ID:$OS_VERSION_ID" in
        ubuntu:22.04) export DISTRO=22 ;;
        ubuntu:24.04) export DISTRO=24 ;;
        debian:11) export DISTRO=11 ;;
        debian:12) export DISTRO=12 ;;
        debian:13) export DISTRO=13 ;;
    esac
}

function is_ubuntu_noble {
    detect_os_compat >/dev/null 2>&1 || return 1
    [ "$OS_ID" = "ubuntu" ] && [ "$OS_VERSION_ID" = "24.04" ] && [ "$OS_CODENAME" = "noble" ]
}

function apt_package_available {
    local package="$1"
    local candidate

    candidate=$(apt-cache policy "$package" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')
    [ -n "$candidate" ] && [ "$candidate" != "(none)" ]
}

# Install packages only after confirming that every required package has an APT
# candidate. This prevents a single renamed package from aborting a long install
# half way through on newer Ubuntu releases.
function apt_install_required {
    local missing=()
    local package

    for package in "$@"; do
        if ! apt_package_available "$package"; then
            missing+=("$package")
        fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        print_error "Required package(s) unavailable for ${OS_PRETTY_NAME:-this system}: ${missing[*]}"
        return 1
    fi

    hide_output sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
        apt-get install -y "$@"
}

# Optional packages improve compatibility with some coins or UI features but do
# not make the base pool installation fail when a distribution drops one.
function apt_install_optional {
    local package
    for package in "$@"; do
        if apt_package_available "$package"; then
            hide_output sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
                apt-get install -y "$package"
        else
            print_warning "Optional package not available; skipping: $package"
        fi
    done
}

function enable_ubuntu_universe {
    detect_os_compat >/dev/null 2>&1 || return 1
    if [ "$OS_ID" != "ubuntu" ]; then
        return 0
    fi

    # Fresh cloud images may not have current APT indexes yet. Refresh first so
    # software-properties-common can be installed before enabling Universe.
    hide_output sudo apt-get update
    hide_output sudo apt-get install -y software-properties-common
    # add-apt-repository is idempotent and works with Noble's deb822 sources.
    hide_output sudo add-apt-repository -y universe
    hide_output sudo apt-get update
}

# Configure PHP 8.1 using the repository intended for the detected platform.
# Ubuntu Noble/Jammy use ppa:ondrej/php; packages.sury.org is reserved for Debian.
function configure_php81_repository {
    detect_os_compat || return 1

    # Repository helpers are also callable during upgrades, so do not assume a
    # previous installer stage has refreshed the package indexes.
    hide_output sudo apt-get update
    apt_install_required software-properties-common ca-certificates lsb-release curl gnupg2

    if [ "$OS_ID" = "ubuntu" ]; then
        case "$OS_VERSION_ID" in
            22.04|24.04)
                enable_ubuntu_universe
                if ! grep -Rqs "ppa.launchpadcontent.net/ondrej/php\|ondrej/php" \
                    /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
                    print_status "Adding Ondrej PHP PPA for Ubuntu $OS_VERSION_ID ($OS_CODENAME)"
                    hide_output sudo add-apt-repository -y ppa:ondrej/php
                fi
                ;;
            *)
                print_error "PHP 8.1 repository is not configured for Ubuntu $OS_VERSION_ID"
                return 1
                ;;
        esac
    elif [ "$OS_ID" = "debian" ]; then
        sudo install -d -m 0755 /etc/apt/keyrings
        if [ ! -f /etc/apt/keyrings/php.gpg ]; then
            curl -fsSL https://packages.sury.org/php/apt.gpg | \
                sudo gpg --dearmor -o /etc/apt/keyrings/php.gpg
        fi
        echo "deb [signed-by=/etc/apt/keyrings/php.gpg] https://packages.sury.org/php/ $OS_CODENAME main" | \
            sudo tee /etc/apt/sources.list.d/php.list >/dev/null
    else
        print_error "Unsupported operating system for PHP repository setup: $OS_ID $OS_VERSION_ID"
        return 1
    fi

    hide_output sudo apt-get update

    if ! apt_package_available php8.1-fpm; then
        print_error "php8.1-fpm is not available after repository setup"
        return 1
    fi
}

function install_php81_stack {
    configure_php81_repository || return 1

    print_status "Installing PHP 8.1 runtime and required YiiMP extensions"
    apt_install_required \
        php8.1 php8.1-cli php8.1-cgi php8.1-common php8.1-fpm php8.1-opcache \
        php8.1-curl php8.1-gd php8.1-imap php8.1-intl php8.1-mbstring \
        php8.1-mysql php8.1-pspell php8.1-sqlite3 php8.1-tidy php8.1-xmlrpc \
        php8.1-xsl php8.1-zip

    apt_install_optional php8.1-imagick php8.1-memcache php8.1-memcached php-pear php-auth-sasl

    sudo systemctl enable php8.1-fpm >/dev/null 2>&1 || true
    sudo systemctl restart php8.1-fpm
}

# Select a deterministic compiler for the legacy YiiMP stratum without changing
# the system-wide gcc/g++ alternatives. Ubuntu 24.04 ships GCC 13 by default but
# also provides GCC 10 in Universe, which is used for the legacy stratum build.
function select_stratum_compiler {
    detect_os_compat || return 1

    if is_ubuntu_noble; then
        enable_ubuntu_universe
        apt_install_required gcc-10 g++-10
        STRATUM_CC=/usr/bin/gcc-10
        STRATUM_CXX=/usr/bin/g++-10
    elif apt_package_available gcc-10 && apt_package_available g++-10; then
        apt_install_required gcc-10 g++-10
        STRATUM_CC=/usr/bin/gcc-10
        STRATUM_CXX=/usr/bin/g++-10
    else
        STRATUM_CC=$(command -v gcc)
        STRATUM_CXX=$(command -v g++)
    fi

    if [ -z "$STRATUM_CC" ] || [ -z "$STRATUM_CXX" ]; then
        print_error "Unable to select a C/C++ compiler"
        return 1
    fi

    export STRATUM_CC STRATUM_CXX
    print_info "Stratum compiler: $STRATUM_CC / $STRATUM_CXX"
}

function apt_update {
	sudo apt-get update
}

function apt_upgrade {
	hide_output sudo apt-get upgrade -y
}

function apt_dist_upgrade {
	hide_output sudo apt-get dist-upgrade -y
}

function apt_autoremove {
	hide_output sudo apt-get autoremove -y
}

function ufw_allow {
	if [ -z "$DISABLE_FIREWALL" ]; then
		sudo ufw allow $1 >/dev/null
	fi
}

function restart_service {
	hide_output sudo service $1 restart
}

## Dialog Functions ##
function message_box {
	dialog --title "$1" --msgbox "$2" 0 0
}

function input_box {
	# input_box "title" "prompt" "defaultvalue" VARIABLE
	# The user's input will be stored in the variable VARIABLE.
	# The exit code from dialog will be stored in VARIABLE_EXITCODE.
	declare -n result=$4
	declare -n result_code=$4_EXITCODE
	result=$(dialog --stdout --title "$1" --inputbox "$2" 0 0 "$3")
	result_code=$?
}

function input_menu {
	# input_menu "title" "prompt" "tag item tag item" VARIABLE
	# The user's input will be stored in the variable VARIABLE.
	# The exit code from dialog will be stored in VARIABLE_EXITCODE.
	declare -n result=$4
	declare -n result_code=$4_EXITCODE
	local IFS=^$'\n'
	result=$(dialog --stdout --title "$1" --menu "$2" 0 0 0 $3)
	result_code=$?
}

function get_publicip_from_web_service {
	# This seems to be the most reliable way to determine the
	# machine's public IP address: asking a very nice web API
	# for how they see us. Thanks go out to icanhazip.com.
	# See: https://major.io/icanhazip-com-faq/
	#
	# Pass '4' or '6' as an argument to this function to specify
	# what type of address to get (IPv4, IPv6).
	curl -$1 --fail --silent --max-time 15 icanhazip.com 2>/dev/null
}

function get_default_privateip {
	# Return the IP address of the network interface connected
	# to the Internet.
	#
	# Pass '4' or '6' as an argument to this function to specify
	# what type of address to get (IPv4, IPv6).
	#
	# We used to use `hostname -I` and then filter for either
	# IPv4 or IPv6 addresses. However if there are multiple
	# network interfaces on the machine, not all may be for
	# reaching the Internet.
	#
	# Instead use `ip route get` which asks the kernel to use
	# the system's routes to select which interface would be
	# used to reach a public address. We'll use 8.8.8.8 as
	# the destination. It happens to be Google Public DNS, but
	# no connection is made. We're just seeing how the box
	# would connect to it. There many be multiple IP addresses
	# assigned to an interface. `ip route get` reports the
	# preferred. That's good enough for us. See issue #121.
	#
	# With IPv6, the best route may be via an interface that
	# only has a link-local address (fe80::*). These addresses
	# are only unique to an interface and so need an explicit
	# interface specification in order to use them with bind().
	# In these cases, we append "%interface" to the address.
	# See the Notes section in the man page for getaddrinfo and
	# https://discourse.mailinabox.email/t/update-broke-mailinabox/34/9.
	#
	# Also see ae67409603c49b7fa73c227449264ddd10aae6a9 and
	# issue #3 for why/how we originally added IPv6.

	target=8.8.8.8

	# For the IPv6 route, use the corresponding IPv6 address
	# of Google Public DNS. Again, it doesn't matter so long
	# as it's an address on the public Internet.
	if [ "$1" == "6" ]; then target=2001:4860:4860::8888; fi

	# Get the route information.
	route=$(ip -$1 -o route get $target | grep -v unreachable)

	# Parse the address out of the route information.
	address=$(echo $route | sed "s/.* src \([^ ]*\).*/\1/")

	if [[ "$1" == "6" && $address == fe80:* ]]; then
		# For IPv6 link-local addresses, parse the interface out
		# of the route information and append it with a '%'.
		interface=$(echo $route | sed "s/.* dev \([^ ]*\).*/\1/")
		address=$address%$interface
	fi

	echo $address

}


# Yiimpool functions

# Function to upgrade stratum
upgrade_stratum() {
    log_message "$YELLOW" "Upgrading stratum..."

    local yiimp_dir="$STORAGE_ROOT/yiimp/yiimp_setup/yiimp"
    local stratum_dir="$STORAGE_ROOT/yiimp/site/stratum"

    if [ -d "$yiimp_dir" ]; then
        sudo rm -rf "$yiimp_dir"
    fi

    log_message "$GREEN" "Cloning fresh YiiMP repository..."
    if ! sudo git clone "${YiiMPRepo}" "$yiimp_dir"; then
        log_message "$RED" "Failed to clone YiiMP repository. Exiting..."
        return 1
    fi

    log_message "$GREEN" "Selecting a compatible stratum compiler..."
    select_stratum_compiler || return 1
    log_message "$GREEN" "Using $STRATUM_CC / $STRATUM_CXX"

    cd "$yiimp_dir/stratum" || return 1
    sudo git submodule init
    sudo git submodule update

    log_message "$GREEN" "Building stratum components..."
    if ! sudo env CC="$STRATUM_CC" CXX="$STRATUM_CXX" make -C algos; then
        log_message "$RED" "Failed to build algos."
        return 1
    fi
    if ! sudo env CC="$STRATUM_CC" CXX="$STRATUM_CXX" make -C sha3; then
        log_message "$RED" "Failed to build sha3."
        return 1
    fi
    if ! sudo env CC="$STRATUM_CC" CXX="$STRATUM_CXX" make -C iniparser; then
        log_message "$RED" "Failed to build iniparser."
        return 1
    fi

    cd secp256k1 || return 1
    sudo chmod +x autogen.sh
    hide_output sudo ./autogen.sh
    hide_output sudo env CC="$STRATUM_CC" CXX="$STRATUM_CXX" \
        ./configure --enable-experimental --enable-module-ecdh --with-bignum=no --enable-endomorphism
    hide_output sudo env CC="$STRATUM_CC" CXX="$STRATUM_CXX" make

    cd "$yiimp_dir/stratum" || return 1
    if ! sudo env CC="$STRATUM_CC" CXX="$STRATUM_CXX" make buildonly; then
        log_message "$RED" "Failed to build stratum."
        return 1
    fi

    sudo systemctl stop yiimp_stratum 2>/dev/null || true

    if [ -d "$stratum_dir/config" ]; then
        sudo rm -rf "$stratum_dir/config_backup"
        sudo cp -a "$stratum_dir/config" "$stratum_dir/config_backup"
    fi

    log_message "$GREEN" "Installing stratum..."
    sudo install -m 0750 stratum "$stratum_dir/stratum" || return 1

    if [ -d "$stratum_dir/config_backup" ]; then
        sudo mkdir -p "$stratum_dir/config"
        sudo cp -a "$stratum_dir/config_backup/." "$stratum_dir/config/"
        sudo rm -rf "$stratum_dir/config_backup"
    fi

    log_message "$GREEN" "Installing Stratum management tools..."
    if ! bash "$HOME/sqsyiimp/stratum_manager/install.sh"; then
        log_message "$RED" "Failed to install Stratum management tools."
        return 1
    fi

    if [ -f "$yiimp_dir/web/yaamp/core/functions/yaamp.php" ]; then
        sudo cp -a "$yiimp_dir/web/yaamp/core/functions/yaamp.php" \
            "$STORAGE_ROOT/yiimp/site/web/yaamp/core/functions/"
    fi

    log_message "$GREEN" "Stratum upgrade completed successfully!"
    return 0
}


display_version_info() {
    print_status "Installed SQSYIIMP installer version: $VERSION"
    print_info "Checking GitHub for a newer release tag"

    cd $HOME/sqsyiimp
    # SQSYIIMP update check using the public GitHub repository.
    # No SSH alias, authentication or GitHub Release is required.
    SQSYIIMP_PUBLIC_REPO="https://github.com/SabiasQueSpace/SQSYIIMP_install.git"

    LATEST_TAG="$(
        git ls-remote \
            --tags \
            --refs \
            "${SQSYIIMP_PUBLIC_REPO}" \
            'v*' 2>/dev/null |
        awk -F/ '{print $3}' |
        sort -V |
        tail -n 1
    )"

    if [[ -z "${LATEST_TAG}" ]]; then

        print_warning "Unable to check GitHub tags. Continuing with ${VERSION}."
        LATEST_TAG="${VERSION}"

    elif [[ "${LATEST_TAG}" == "${VERSION}" ]]; then

        print_success "SQSYIIMP ${VERSION} is up to date."

    elif [[ "$(printf '%s
%s
' "${VERSION}" "${LATEST_TAG}" | sort -V | tail -n 1)" != "${LATEST_TAG}" ]]; then

        # Installed version is newer than the latest public tag.
        LATEST_TAG="${VERSION}"

    fi

    if [ "$VERSION" != "$LATEST_TAG" ]; then
        print_warning "New version available: $LATEST_TAG"
        print_status "Update the installer from Git? (y/n)"
        read -r update_choice

        if [[ "$update_choice" =~ ^[Yy]$ ]]; then
            cd $HOME/sqsyiimp/yiimp_upgrade
            source upgrade.sh --full
        else
            print_info "Update skipped"
        fi
    else
        print_success "You are on the latest tagged version"
    fi
    echo
}

BOLD='\033[1m'
DIM='\033[2m'

# ── Title ──────────────────────── (cyan bold, fills terminal width)
print_header() {
    local title="$1"
    local width
    width=$(tput cols 2>/dev/null || echo 60)
    local prefix="── ${title} "
    # ${#prefix} counts visual characters correctly in a UTF-8 locale;
    # subtract 4 for the two '─' chars in the prefix (each is 1 visual col
    # but bash counts them as 1 char each — no adjustment needed on modern bash).
    # Use printf "%.0s─" to repeat the box-drawing char without tr byte issues.
    local remaining=$(( width - ${#prefix} ))
    [ "$remaining" -lt 2 ] && remaining=2
    local fill
    fill=$(printf "%.0s─" $(seq 1 "$remaining"))
    echo -e "\n\033[1;36m${prefix}${fill}${NC}\n"
}

#   →  message  (cyan arrow)
print_status() {
    echo -e "  \033[0;36m→${NC}  $1"
}

#   ✔  message  (green tick)
print_success() {
    echo -e "  ${GREEN}✔${NC}  $1"
}

#   ✖  message  (red bold)
print_error() {
    echo -e "  ${RED}${BOLD}✖${NC}  ${BOLD}$1${NC}"
}

#   ⚠  message  (yellow)
print_warning() {
    echo -e "  ${YELLOW}⚠${NC}  $1"
}

#   ·  message  (dim)
print_info() {
    echo -e "  ${DIM}·${NC}  $1"
}

# full-width thin divider line (dim)
print_divider() {
    local width
    width=$(tput cols 2>/dev/null || echo 60)
    local fill
    fill=$(printf "%.0s─" $(seq 1 "$width"))
    echo -e "\n${DIM}${fill}${NC}\n"
}


############################################################
# SQSYIIMP PUBLIC UPDATE HELPERS
############################################################

sqsyiimp_get_installed_version() {
    awk -F= '
        $1 == "VERSION" {
            gsub(/[[:space:]"\047]/, "", $2)
            print $2
            exit
        }
    ' /etc/yiimpoolversion.conf 2>/dev/null
}

sqsyiimp_get_latest_tag() {
    local repo="https://github.com/SabiasQueSpace/SQSYIIMP_install.git"
    local latest=""

    command -v git >/dev/null 2>&1 || return 1

    latest="$(
        git ls-remote \
            --tags \
            --refs \
            "$repo" \
            'v*' 2>/dev/null |
        awk -F/ '{print $3}' |
        sort -V |
        tail -n 1
    )"

    [[ -n "$latest" ]] || return 1

    printf '%s\n' "$latest"
}

sqsyiimp_version_is_newer() {
    local installed="${1:-}"
    local available="${2:-}"

    [[ -n "$installed" && -n "$available" ]] || return 1
    [[ "$installed" != "$available" ]] || return 1

    [[ "$(
        printf '%s\n%s\n' "$installed" "$available" |
        sort -V |
        tail -n 1
    )" == "$available" ]]
}

sqsyiimp_repo_dir() {
    local current_user="${SUDO_USER:-${USER:-}}"
    local user_home=""

    if [[ -n "$current_user" ]]; then
        user_home="$(
            getent passwd "$current_user" 2>/dev/null |
            cut -d: -f6
        )"
    fi

    [[ -n "$user_home" ]] || user_home="$HOME"

    printf '%s\n' "${SQSYIIMP_REPO_DIR:-${user_home}/sqsyiimp}"
}

sqsyiimp_run_updater() {
    local repo

    repo="$(sqsyiimp_repo_dir)"

    if [[ ! -f "$repo/install/bootstrap_upgrade.sh" ]]; then
        echo "ERROR: SQSYIIMP updater not found:"
        echo "       $repo/install/bootstrap_upgrade.sh"
        return 1
    fi

    bash "$repo/install/bootstrap_upgrade.sh"
}

############################################################
# END SQSYIIMP PUBLIC UPDATE HELPERS
############################################################
