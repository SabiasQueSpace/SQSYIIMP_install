#!/usr/bin/env bash

##################################################################################
# This is the entry point for configuring the system.                            #
# Source https://mailinabox.email/ https://github.com/mail-in-a-box/mailinabox   #
# SQSYIIMP - SabiasQue.Space
##################################################################################

source /etc/yiimpoolversion.conf
source /etc/functions.sh
cd "$HOME/sqsyiimp/install"
clear

# Welcome
message_box "SQSYIIMP Installer $VERSION" \
"Hello and thanks for using SQSYIIMP — SabiasQue.Space!
\n\nInstallation for the most part is fully automated. In most cases any user responses that are needed are asked prior to the installation.
\n\nNOTE: You should only install this on a brand new server."

# Root warning message box
message_box "SQSYIIMP Installer $VERSION" \
"WARNING: You are about to run this script as root!
\n\nThe program will create a new user account with sudo privileges.
\n\nThe next step, you will be asked to create a new user account, you can name it whatever you want."

# Ask if SSH key or password user
dialog --title "Create New User With SSH Key" \
    --yesno "Do you want to create new user with SSH key login?
Selecting no will create user with password login only." 7 60
response=$?
case $response in
    0) UsingSSH=yes ;;
    1) UsingSSH=no ;;
    255) echo "[ESC] key pressed." ;;
esac

##############################################################################
# SSH Key Login Path
##############################################################################
if [[ "$UsingSSH" == "yes" ]]; then
    clear

    if [ -z "${yiimpadmin:-}" ]; then
        DEFAULT_yiimpadmin=yiimpadmin
        input_box "New username" \
            "Please enter your new username.
      \n\nUser Name:" \
            "${DEFAULT_yiimpadmin}" \
            yiimpadmin

        if [ -z "${yiimpadmin}" ]; then
            # user hit ESC/cancel
            exit
        fi
    fi

    if [ -z "${ssh_key:-}" ]; then
        clear
        echo -e "${YELLOW}Open PuTTY Key Generator, generate your key pair, and copy the text from${NC}"
        echo -e "${GREEN}'Public key for pasting into OpenSSH authorized_keys file'${NC}${YELLOW} box.${NC}"
        echo -e "${YELLOW}To paste in this terminal use: ${GREEN}ctrl+shift+right-click${NC}"
        echo
        echo -ne "${YELLOW}Paste your SSH public key and press Enter: ${NC}"
        read -r ssh_key < /dev/tty

        if [ -z "${ssh_key}" ]; then
            echo -e "${RED}No key entered. Exiting.${NC}"
            exit
        fi
    fi

    clear

    # Add user with disabled password (SSH key authentication only)
    echo -e "$YELLOW => Adding new user and setting SSH key... <= ${NC}"
    sudo adduser "${yiimpadmin}" --gecos "First Last,RoomNumber,WorkPhone,HomePhone" --disabled-password
    sudo usermod -aG sudo "${yiimpadmin}"

    # Create SSH key structure
    # Home directory must NOT be group/world-writable (SSH StrictModes check)
    chmod 755 "/home/${yiimpadmin}"
    mkdir -p "/home/${yiimpadmin}/.ssh"
    chown "${yiimpadmin}:${yiimpadmin}" "/home/${yiimpadmin}/.ssh"
    chmod 700 "/home/${yiimpadmin}/.ssh"

    # Write the public key, then lock down permissions
    # (order matters: write first so permissions are set on final content)
    authkeys="/home/${yiimpadmin}/.ssh/authorized_keys"
    printf '%s\n' "$ssh_key" > "$authkeys"
    chown "${yiimpadmin}:${yiimpadmin}" "$authkeys"
    chmod 600 "$authkeys"

    # Enable the yiimpool command
    printf '# yiimp\n# It needs passwordless sudo functionality.\n%s ALL=(ALL) NOPASSWD:ALL\n' \
        "${yiimpadmin}" | sudo -E tee /etc/sudoers.d/"${yiimpadmin}" >/dev/null 2>&1

    printf '#!/usr/bin/env bash\ncd ~/sqsyiimp/install\nbash start.sh\n' \
        | sudo -E tee /usr/bin/yiimpool >/dev/null 2>&1
    sudo chmod +x /usr/bin/yiimpool

    # Configure sshd for key-based authentication
    if [ -d /etc/ssh/sshd_config.d ]; then
        # Modern Ubuntu/Debian (20.04+): use a drop-in file
        sudo tee /etc/ssh/sshd_config.d/10-yiimpool.conf >/dev/null <<'SSHEOF'
# SQSYIIMP: enforce public-key-only authentication
PubkeyAuthentication yes
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PasswordAuthentication no
SSHEOF
        sudo chmod 644 /etc/ssh/sshd_config.d/10-yiimpool.conf
        # Neutralise cloud-init PasswordAuthentication yes override if present
        if [ -f /etc/ssh/sshd_config.d/50-cloud-init.conf ]; then
            sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' \
                /etc/ssh/sshd_config.d/50-cloud-init.conf
        fi
    else
        # Older systems: edit the main sshd_config directly.
        # _sshd_set replaces the directive if it already exists (commented or not),
        # and appends it at the end of the file if it is completely absent.
        _sshd_set() {
            local key=$1 val=$2
            if grep -qE "^#*${key}[[:space:]]" /etc/ssh/sshd_config; then
                sudo sed -i "s/^#*${key}[[:space:]].*/${key} ${val}/" /etc/ssh/sshd_config
            else
                echo "${key} ${val}" | sudo tee -a /etc/ssh/sshd_config >/dev/null
            fi
        }
        _sshd_set PubkeyAuthentication yes
        _sshd_set KbdInteractiveAuthentication no
        _sshd_set ChallengeResponseAuthentication no
        _sshd_set PasswordAuthentication no
    fi

    # Restart SSH to apply the new settings
    echo -e "$YELLOW => Restarting SSH service to apply key-auth settings... <= $NC"
    sudo systemctl restart ssh 2>/dev/null || sudo systemctl restart sshd 2>/dev/null || sudo service ssh restart
    echo -e "$GREEN => SSH service restarted. $NC"

    # Check required files and set global variables
    cd "$HOME/sqsyiimp/install"
    source pre_setup.sh

    # Create the dedicated storage/service account and its data root.
    STORAGE_GROUP="${STORAGE_GROUP:-${STORAGE_USER}}"

    if ! getent group "$STORAGE_GROUP" >/dev/null 2>&1; then
        sudo groupadd "$STORAGE_GROUP"
    fi

    if ! id -u "$STORAGE_USER" >/dev/null 2>&1; then
        sudo useradd             --create-home             --home-dir "$STORAGE_ROOT"             --gid "$STORAGE_GROUP"             --shell /usr/sbin/nologin             "$STORAGE_USER"
    fi

    sudo install -d         -o "$STORAGE_USER"         -g "$STORAGE_GROUP"         -m 755         "$STORAGE_ROOT"

    # Save the global options in /etc/yiimpool.conf so that standalone
    # tools know where to look for data.
    sudo tee /etc/yiimpool.conf >/dev/null 2>&1 <<YIIMPCNF
STORAGE_USER=${STORAGE_USER}
STORAGE_GROUP=${STORAGE_GROUP}
STORAGE_ROOT=${STORAGE_ROOT}
PUBLIC_IP=${PUBLIC_IP}
PUBLIC_IPV6=${PUBLIC_IPV6}
DISTRO=${DISTRO}
PRIVATE_IP=${PRIVATE_IP}
YIIMPCNF

sudo cp -r ~/sqsyiimp "/home/${yiimpadmin}/"
    cd ~
    sudo setfacl -m "u:${yiimpadmin}:rwx" "/home/${yiimpadmin}/sqsyiimp"
    sudo rm -r "$HOME/sqsyiimp"
    clear
    term_art
    echo
    echo -e "${YELLOW}Setup information:${NC}"
    echo
    echo -e "${MAGENTA}USERNAME:         ${GREEN}${yiimpadmin}${NC}"
    echo -e "${MAGENTA}STORAGE_USER:     ${GREEN}${STORAGE_USER}${NC}"
    echo -e "${MAGENTA}STORAGE_ROOT:     ${GREEN}${STORAGE_ROOT}${NC}"
    echo -e "${MAGENTA}PUBLIC_IPV6:      ${GREEN}${PUBLIC_IPV6}${NC}"
    echo -e "${MAGENTA}DISTRO:           ${GREEN}${DISTRO}${NC}"
    echo -e "${MAGENTA}FIRST_TIME_SETUP: ${GREEN}${FIRST_TIME_SETUP}${NC}"
    echo -e "${MAGENTA}PRIVATE_IP:       ${GREEN}${PRIVATE_IP}${NC}"
    echo
    echo -e "$YELLOW New User:$MAGENTA ${yiimpadmin} $GREEN created! $YELLOW Make sure you save your $RED private key!${NC}"
    echo
    echo -e "$RED Please reboot the system and log in as $GREEN ${yiimpadmin} $YELLOW and type $GREEN yiimpool $YELLOW to $GREEN continue $YELLOW setup...$NC"
    echo
    echo -e "$YELLOW To connect with PuTTY, go to: $GREEN Connection > SSH > Auth > Credentials$YELLOW and browse to your$RED .ppk$YELLOW private key file before connecting.${NC}"
    exit 0
fi

##############################################################################
# Password Login Path
##############################################################################

# Collect new username if not already set
if [ -z "${yiimpadmin:-}" ]; then
    DEFAULT_yiimpadmin=yiimpadmin
    input_box "Create new username" \
        "Please enter your new username.
  \n\nUser Name:" \
        "${DEFAULT_yiimpadmin}" \
        yiimpadmin

    if [ -z "${yiimpadmin}" ]; then
        # user hit ESC/cancel
        exit
    fi
fi

# Collect password
if [ -z "${RootPassword:-}" ]; then
    DEFAULT_RootPassword=$(openssl rand -base64 8 | tr -d "=+/")
    input_box "User Password" \
        "Enter your new user password or use this randomly system generated one.
  \n\nUnfortunately dialog doesnt let you copy. So you have to write it down.
  \n\nUser password:" \
        "${DEFAULT_RootPassword}" \
        RootPassword

    if [ -z "${RootPassword}" ]; then
        # user hit ESC/cancel
        exit
    fi
fi

clear

dialog --title "Verify Your input" \
    --yesno "Please verify your answers before you continue:
New User Name : ${yiimpadmin}
New User Pass : ${RootPassword}" 8 60

# Get exit status
# 0 means user hit [yes] button.
# 1 means user hit [no] button.
# 255 means user hit [Esc] key.
response=$?
case $response in

0)
    clear
    echo -e "$YELLOW => Adding new user and password... <= ${NC}"

    sudo adduser "${yiimpadmin}" --gecos "First Last,RoomNumber,WorkPhone,HomePhone" --disabled-password
    printf '%s\n%s\n' "${RootPassword}" "${RootPassword}" | passwd "${yiimpadmin}"
    sudo usermod -aG sudo "${yiimpadmin}"

    # Enable the yiimpool command
    printf '# yiimp\n# It needs passwordless sudo functionality.\n%s ALL=(ALL) NOPASSWD:ALL\n' \
        "${yiimpadmin}" | sudo -E tee /etc/sudoers.d/"${yiimpadmin}" >/dev/null 2>&1

    printf '#!/usr/bin/env bash\ncd ~/sqsyiimp/install\nbash start.sh\n' \
        | sudo -E tee /usr/bin/yiimpool >/dev/null 2>&1
    sudo chmod +x /usr/bin/yiimpool

    # Check required files and set global variables
    cd "$HOME/sqsyiimp/install"
    source pre_setup.sh

    # Create the dedicated storage/service account and its data root.
    STORAGE_GROUP="${STORAGE_GROUP:-${STORAGE_USER}}"

    if ! getent group "$STORAGE_GROUP" >/dev/null 2>&1; then
        sudo groupadd "$STORAGE_GROUP"
    fi

    if ! id -u "$STORAGE_USER" >/dev/null 2>&1; then
        sudo useradd             --create-home             --home-dir "$STORAGE_ROOT"             --gid "$STORAGE_GROUP"             --shell /usr/sbin/nologin             "$STORAGE_USER"
    fi

    sudo install -d         -o "$STORAGE_USER"         -g "$STORAGE_GROUP"         -m 755         "$STORAGE_ROOT"

    # Save the global options in /etc/yiimpool.conf so that standalone
    # tools know where to look for data.
    sudo tee /etc/yiimpool.conf >/dev/null 2>&1 <<YIIMPCNF
STORAGE_USER=${STORAGE_USER}
STORAGE_GROUP=${STORAGE_GROUP}
STORAGE_ROOT=${STORAGE_ROOT}
PUBLIC_IP=${PUBLIC_IP}
PUBLIC_IPV6=${PUBLIC_IPV6}
DISTRO=${DISTRO}
PRIVATE_IP=${PRIVATE_IP}
YIIMPCNF

sudo cp -r ~/sqsyiimp "/home/${yiimpadmin}/"
    cd ~
    sudo setfacl -m "u:${yiimpadmin}:rwx" "/home/${yiimpadmin}/sqsyiimp"
    sudo rm -r "$HOME/sqsyiimp"
    clear
    term_art
    echo
    echo -e "${YELLOW}Setup information:${NC}"
    echo
    echo -e "${MAGENTA}USERNAME:         ${GREEN}${yiimpadmin}${NC}"
    echo -e "${MAGENTA}STORAGE_USER:     ${GREEN}${STORAGE_USER}${NC}"
    echo -e "${MAGENTA}STORAGE_ROOT:     ${GREEN}${STORAGE_ROOT}${NC}"
    echo -e "${MAGENTA}PUBLIC_IPV6:      ${GREEN}${PUBLIC_IPV6}${NC}"
    echo -e "${MAGENTA}DISTRO:           ${GREEN}${DISTRO}${NC}"
    echo -e "${MAGENTA}FIRST_TIME_SETUP: ${GREEN}${FIRST_TIME_SETUP}${NC}"
    echo -e "${MAGENTA}PRIVATE_IP:       ${GREEN}${PRIVATE_IP}${NC}"
    echo
    echo -e "$YELLOW New User:$MAGENTA ${yiimpadmin} $GREEN created!${NC}"
    echo
    echo -e "$RED Please reboot the system and log in as: $GREEN ${yiimpadmin} $YELLOW and type $GREEN yiimpool $YELLOW to $GREEN continue $YELLOW setup...$NC"
    ;;

1)
    clear
    bash "$(basename "$0")" && exit
    ;;

255) ;;

esac
