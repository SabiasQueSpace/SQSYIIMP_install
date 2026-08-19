#!/usr/bin/env bash

##################################################################################
# This is the entry point for configuring the system.                            #
# Source: https://mailinabox.email/ https://github.com/mail-in-a-box/mailinabox   #
# SQSYIIMP - SabiasQue.Space
##################################################################################

# Load required functions and configurations
source /etc/functions.sh
source /etc/yiimpool.conf
source "$HOME/sqsyiimp/yiimp_single/.wireguard.install.cnf"
source "$STORAGE_ROOT/yiimp/.yiimp.conf"

if [ -f "$STORAGE_ROOT/yiimp/.wireguard_public.conf" ]; then
  source "$STORAGE_ROOT/yiimp/.wireguard_public.conf"
else
  wireguard=false
fi


# Get the IP addresses of the local network interface(s).
if [ -z "${NewStratumInternalIP:-}" ]; then
DEFAULT_NewStratumInternalIP='10.0.0.x'
input_box "Stratum Server Private IP" \
"Enter the private IP address of the Stratum Server, as given to you by your provider.
\n\nIf you do not have one from your provider enter the IP you assigned with WireGuard.
\n\nPrivate IP address:" \
"$DEFAULT_NewStratumInternalIP" \
NewStratumInternalIP

if [ -z "$NewStratumInternalIP" ]; then
# user hit ESC/cancel
exit
fi
fi

if [ -z "${NewStratumUser:-}" ]; then
DEFAULT_NewStratumUser='yiimpadmin'
input_box "Stratum Server User Name" \
"Enter the user name of the Stratum Server.
\n\nThis is required for setup to complete.
\n\nStratum Server User Name:" \
"$DEFAULT_NewStratumUser" \
NewStratumUser

if [ -z "$NewStratumUser" ]; then
# user hit ESC/cancel
exit
fi
fi

if [ -z "${NewStratumPass:-}" ]; then
DEFAULT_NewStratumPass=$(openssl rand -base64 29 | tr -d "=+/")
input_box "Stratum Server User Password" \
"Enter the user password of the Stratum Server.
\n\nThis is required for setup to complete.
\n\nWhen pasting your password CTRL+V does NOT work, you must use SHIFT+RightMouseClick or SHIFT+INSERT.
\n\nStratum Server User Password:" \
"$DEFAULT_NewStratumPass" \
NewStratumPass

if [ -z "$NewStratumPass" ]; then
# user hit ESC/cancel
exit
fi
fi

if [ -z "${NewStratumURL:-}" ]; then
DEFAULT_NewStratumURL=stratum.$DomainName
input_box "Stratum URL" \
"Enter your stratum URL. It is recommended to use another subdomain such as stratum.$DomainName
\n\nDo not add www. to the domain name.
\n\nStratum URL:" \
"$DEFAULT_NewStratumURL" \
NewStratumURL

if [ -z "$NewStratumURL" ]; then
# user hit ESC/cancel
exit
fi
fi

if [ -z "${blckntifypass:-}" ]; then
DEFAULT_blckntifypass=""
input_box "Blocknotify Password" \
"Enter the existing blocknotify password from the first stratum server.
\n\nTo retrieve it, log in to your first stratum server and run:
\n\ncat $STORAGE_ROOT/yiimp/site/stratum/config/a5a.conf
\n\nThe blocknotify password is the first password in the TCP section.
\n\nUse SHIFT+RightMouseClick or SHIFT+INSERT to paste.
\n\nBlocknotify Password:" \
"$DEFAULT_blckntifypass" \
blckntifypass

if [ -z "$blckntifypass" ]; then
# user hit ESC/cancel
exit
fi
fi

# Generate random conf file name, random StratumDBUser and StratumDBPassword.
# To increase security we randomly generate the stratum DB user and password for each installation.
# We do it here to save the variables to the new stratum conf file.
generate=$(openssl rand -base64 9 | tr -d "=+/")
StratumDBUser=Stratum$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 13 ; echo '')
StratumUserDBPassword=$(openssl rand -base64 29 | tr -d "=+/")

# Save stratum configuration to a randomly named conf file, then copy to .newconf.conf
# so that subsequent scripts (add_stratum_db.sh, setsid_stratum_server.sh) can source it.
echo 'STORAGE_USER='"${STORAGE_USER}"'
STORAGE_ROOT='"${STORAGE_ROOT}"'

DomainName='"${DomainName}"'
StratumURL='"${NewStratumURL}"'
blckntifypass='"${blckntifypass}"'

DBInternalIP='"${DBInternalIP}"'
StratumUser='"${NewStratumUser}"'
StratumPass='"'"''"${NewStratumPass}"''"'"'
StratumInternalIP='"${NewStratumInternalIP}"'

YiiMPDBName='"${YiiMPDBName}"'
DBRootPassword='"'"''"${DBRootPassword}"''"'"'
StratumDBUser='"'"''"${StratumDBUser}"''"'"'
StratumUserDBPassword='"'"''"${StratumUserDBPassword}"''"'"'

wireguard='"'"''"${wireguard}"''"'"'

# Unless you do some serious modifications this installer will not work with any other repo of yiimp!
YiiMPRepo='https://github.com/Kudaraidee/yiimp.git'
' | sudo -E tee "$STORAGE_ROOT/yiimp/.$generate.conf" >/dev/null 2>&1

# Copy the new config to a static name (overwrite if it exists)
sudo cp "$STORAGE_ROOT/yiimp/.$generate.conf" "$STORAGE_ROOT/yiimp/.newconf.conf"