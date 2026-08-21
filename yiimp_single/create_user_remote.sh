#!/usr/bin/env bash

##################################################################################
# This is the entry point for configuring the system.                            #
# Source https://mailinabox.email/ https://github.com/mail-in-a-box/mailinabox   #
# SQSYIIMP - SabiasQue.Space
##################################################################################

export TERM=xterm

if [ -z "${TAG:-}" ]; then
TAG=v2.7.6-sqs5
fi
echo 'VERSION='"${TAG}"'' | sudo -E tee /etc/yiimpoolversion.conf >/dev/null 2>&1

if [ -f /etc/functions.sh ]; then
  source /etc/functions.sh
else
  sudo cp -r /tmp/functions.sh /etc/
  source /etc/functions.sh
fi

ESC_SEQ="\x1b["
NC=${NC:-"\033[0m"} # No Color
RED=$ESC_SEQ"31;01m"
GREEN=$ESC_SEQ"32;01m"
YELLOW=$ESC_SEQ"33;01m"
BLUE=$ESC_SEQ"34;01m"
MAGENTA=$ESC_SEQ"35;01m"
CYAN=$ESC_SEQ"36;01m"

 # Check for user
echo -e "${YELLOW}Installing necessary packages for setup to continue...${NC}\n"

# Validate the remote host before installing release-specific dependencies.
detect_os_compat
if [ "$OS_ID" = "ubuntu" ]; then
    case "$OS_VERSION_ID" in
        22.04) DISTRO=22 ;;
        24.04)
            [ "$OS_CODENAME" = "noble" ] || { echo "Ubuntu 24.04 must use codename noble."; exit 1; }
            DISTRO=24
            ;;
        *)
            echo "This script supports Ubuntu 22.04 LTS and Ubuntu 24.04.x LTS (including 24.04.4). Debian 11/12/13 is also supported."
            exit 1
            ;;
    esac
    enable_ubuntu_universe
elif [ "$OS_ID" = "debian" ]; then
    case "$OS_VERSION_ID" in
        11) DISTRO=11 ;;
        12) DISTRO=12 ;;
        13) DISTRO=13 ;;
        *) echo "This script supports Debian 11/12/13."; exit 1 ;;
    esac
    hide_output sudo apt-get update
else
    echo "Unsupported operating system: ${OS_PRETTY_NAME:-$OS_ID $OS_VERSION_ID}"
    exit 1
fi
export DISTRO

apt_install_required dialog python3 python3-pip acl nano git ca-certificates curl
apt_install_optional figlet lolcat apt-transport-https
echo -e "${GREEN}Installed necessary packages.${NC}\n"

source /etc/yiimpoolversion.conf
source /etc/functions.sh

echo -e "${YELLOW} Beginning remote server setup — this may take a while...${NC}"

# Get logged in user name
whoami=$(whoami)
echo -e "${YELLOW} Modifying existing user $whoami for SQSYIIMP support...${NC}"
sudo usermod -aG sudo ${whoami}

echo '# yiimp
# It needs passwordless sudo functionality.
'""''"${whoami}"''""' ALL=(ALL) NOPASSWD:ALL
' | sudo -E tee /etc/sudoers.d/${whoami} >/dev/null 2>&1

# Set permissions
sudo chmod g-w /etc /etc/default /usr

TOTAL_PHYSICAL_MEM=$(head -n 1 /proc/meminfo | awk '{print $2}')
  if [ $TOTAL_PHYSICAL_MEM -lt 2000000 ]; then
    if [ ! -d /vagrant ]; then
      TOTAL_PHYSICAL_MEM=$(expr \( \( $TOTAL_PHYSICAL_MEM \* 1024 \) / 1000 \) / 1000)
      echo "Your stratum server needs more memory (RAM) to function properly."
      echo "Please provision a machine with at least 2 GB RAM (4 GB recommended)."
      echo "This machine has $TOTAL_PHYSICAL_MEM MB memory."
      exit
    fi
  fi
if [ $TOTAL_PHYSICAL_MEM -lt 4000000 ]; then
  echo "WARNING: Your stratum server has less than 4 GB of memory."
  echo "It may run unreliably under heavy load. 4 GB or more is recommended."
fi

# Check swap
echo -e "${YELLOW} Checking if swap space is needed and creating if so...${NC}"
  SWAP_MOUNTED=$(cat /proc/swaps | tail -n+2)
  SWAP_IN_FSTAB=$(grep "swap" /etc/fstab)
  ROOT_IS_BTRFS=$(grep "\/ .*btrfs" /proc/mounts)
  TOTAL_PHYSICAL_MEM=$(head -n 1 /proc/meminfo | awk '{print $2}')
  AVAILABLE_DISK_SPACE=$(df / --output=avail | tail -n 1)
if
  [ -z "$SWAP_MOUNTED" ] &&
  [ -z "$SWAP_IN_FSTAB" ] &&
  [ ! -e /swapfile ] &&
  [ -z "$ROOT_IS_BTRFS" ] &&
  [ $TOTAL_PHYSICAL_MEM -lt 19000000 ] &&
  [ $AVAILABLE_DISK_SPACE -gt 5242880 ]
then
echo "Adding a swap file to the system..."
  dd if=/dev/zero of=/swapfile bs=2048 count=$((1024*1024)) status=none
    if [ -e /swapfile ]; then
      chmod 600 /swapfile
      hide_output mkswap /swapfile
      swapon /swapfile
    fi
    if swapon -s | grep -q "\/swapfile"; then
      echo "/swapfile  none swap sw 0  0" >> /etc/fstab
    else
      echo "ERROR: Swap allocation failed"
    fi
fi
echo -e "$GREEN Done...$COL_RESET"

ARCHITECTURE=$(uname -m)
  if [ "$ARCHITECTURE" != "x86_64" ] && [ "$ARCHITECTURE" != "aarch64" ]; then
    if [ -z "$ARM" ]; then
      echo "Yiimpool Setup Installer only supports x86_64 and aarch64 architectures and will not work on any other architecture, like 32 bit OS or other ARM variants."
      echo "Your architecture is $ARCHITECTURE"
      exit
    fi
fi

echo -e "${YELLOW} Setting global variables...${NC}"

# If the machine is behind a NAT, inside a VM, etc., it may not know
# its IP address on the public network / the Internet. Ask the Internet
# and possibly confirm with user.
if [ -z "${PUBLIC_IP:-}" ]; then
# Ask the Internet.
GUESSED_IP=$(get_publicip_from_web_service 4 || true)

# On the first run, if we got an answer from the Internet then don't
# ask the user.
if [[ -z "${DEFAULT_PUBLIC_IP:-}" && ! -z "$GUESSED_IP" ]]; then
PUBLIC_IP=$GUESSED_IP

# On later runs, if the previous value matches the guessed value then
# don't ask the user either.
elif [ "${DEFAULT_PUBLIC_IP:-}" == "$GUESSED_IP" ]; then
PUBLIC_IP=$GUESSED_IP
fi

if [ -z "${PUBLIC_IP:-}" ]; then
input_box "Public IP Address" \
"Enter the public IP address of this machine, as given to you by your ISP.
\n\nPublic IP address:" \
"$DEFAULT_PUBLIC_IP" \
PUBLIC_IP

if [ -z "$PUBLIC_IP" ]; then
# user hit ESC/cancel
exit
fi
fi
fi

# Same for IPv6. But it's optional. Also, if it looks like the system
# doesn't have an IPv6, don't ask for one.
if [ -z "${PUBLIC_IPV6:-}" ]; then
	# Ask the Internet.
	GUESSED_IP=$(get_publicip_from_web_service 6 || true)
	MATCHED=0
	if [[ -z "${DEFAULT_PUBLIC_IPV6:-}" && ! -z "$GUESSED_IP" ]]; then
		PUBLIC_IPV6=$GUESSED_IP
	elif [[ "${DEFAULT_PUBLIC_IPV6:-}" == "$GUESSED_IP" ]]; then
		# No IPv6 entered and machine seems to have none, or what
		# the user entered matches what the Internet tells us.
		PUBLIC_IPV6=$GUESSED_IP
		MATCHED=1
	elif [[ -z "${DEFAULT_PUBLIC_IPV6:-}" ]]; then
		DEFAULT_PUBLIC_IPV6=$(get_default_privateip 6 || true)
	fi

	if [[ -z "${PUBLIC_IPV6:-}" && $MATCHED == 0 ]]; then
		input_box "IPv6 Address (Optional)" \
			"Enter the public IPv6 address of this machine, as given to you by your ISP.
			\n\nLeave blank if the machine does not have an IPv6 address.
			\n\nPublic IPv6 address:" \
			${DEFAULT_PUBLIC_IPV6:-} \
			PUBLIC_IPV6

		if [ ! $PUBLIC_IPV6_EXITCODE ]; then
			# user hit ESC/cancel
			exit
		fi
	fi
fi


if [ "$PUBLIC_IP" = "auto" ]; then
PUBLIC_IP=$(get_publicip_from_web_service 4 || get_default_privateip 4)
fi

if [ "$PUBLIC_IPV6" = "auto" ]; then
PUBLIC_IPV6=$(get_publicip_from_web_service 6 || get_default_privateip 6)
fi

# Set STORAGE_USER and STORAGE_ROOT to default values (crypto-data and /home/crypto-data), unless
# we've already got those values from a previous run.
if [ -z "$STORAGE_USER" ]; then
  STORAGE_USER=$([[ -z "$DEFAULT_STORAGE_USER" ]] && echo "crypto-data" || echo "$DEFAULT_STORAGE_USER")
fi
if [ -z "$STORAGE_ROOT" ]; then
  STORAGE_ROOT=$([[ -z "$DEFAULT_STORAGE_ROOT" ]] && echo "/home/$STORAGE_USER" || echo "$DEFAULT_STORAGE_ROOT")
fi

# Create the STORAGE_USER and STORAGE_ROOT directory if they don't already exist.
if ! id -u "$STORAGE_USER" >/dev/null 2>&1; then
  sudo useradd \
    --create-home \
    --home-dir "$STORAGE_ROOT" \
    --shell /usr/sbin/nologin \
    "$STORAGE_USER"
fi

STORAGE_GROUP="${STORAGE_GROUP:-${STORAGE_USER}}"

sudo install -d \
  -o "$STORAGE_USER" \
  -g "$STORAGE_GROUP" \
  -m 755 \
  "$STORAGE_ROOT"

# Save the global options in /etc/yiimpool.conf so that standalone
# tools know where to look for data.
echo 'STORAGE_USER='"${STORAGE_USER}"'
STORAGE_GROUP='"${STORAGE_GROUP}"'
STORAGE_ROOT='"${STORAGE_ROOT}"'
PUBLIC_IP='"${PUBLIC_IP}"'
DISTRO='"${DISTRO}"'
PUBLIC_IPV6='"${PUBLIC_IPV6}"'' | sudo -E tee /etc/yiimpool.conf >/dev/null 2>&1
echo -e "$GREEN Done...$COL_RESET"