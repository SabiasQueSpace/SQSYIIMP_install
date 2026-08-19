#!/usr/bin/env bash

#####################################################
# SQSYIIMP - SabiasQue.Space
#####################################################

source /etc/functions.sh
source /etc/yiimpool.conf
source $STORAGE_ROOT/yiimp/.yiimp.conf
source $HOME/sqsyiimp/yiimp_single/.wireguard.install.cnf

set -eu -o pipefail

function print_error {
    read line file <<<$(caller)
    echo "An error occurred in line $line of file $file:" >&2
    sed "${line}q;d" "$file" >&2
}
trap print_error ERR

if [[ ("$wireguard" == "true") ]]; then
source $STORAGE_ROOT/yiimp/.wireguard.conf
fi

echo -e "$YELLOW => Installing mail system  <= ${NC}"

hide_output sudo apt install -y postfix
hide_output sudo apt install -y mailutils

sudo debconf-set-selections <<<"postfix postfix/mailname string ${PRIMARY_HOSTNAME}"
sudo debconf-set-selections <<<"postfix postfix/main_mailer_type string 'Internet Site'"
# sudo apt-get install mailutils -y

sudo sed -i 's/inet_interfaces = all/inet_interfaces = loopback-only/g' /etc/postfix/main.cf
sudo sed -i 's/myhostname =/# myhostname =/g' /etc/postfix/main.cf
sudo sed -i 's/mydestination/# mydestination/g' /etc/postfix/main.cf
sudo sed -i '/# mydestination/i mydestination = $myhostname, localhost.$mydomain, localhost, $mydomain' /etc/postfix/main.cf
sudo sed -i '/# myhostname =/i myhostname = localhost' /etc/postfix/main.cf

sudo systemctl restart postfix
whoami=$(whoami)

cd $HOME/etc/
sudo touch aliases
sudo sed -i '/postmaster:    root/a root:          '${SupportEmail}'' /etc/aliases
sudo sed -i '/root:/a '$whoami':     '${SupportEmail}'' /etc/aliases
sudo newaliases

sudo adduser $whoami mail
echo -e "$GREEN Mail system complete ${NC}"
set +eu +o pipefail
cd $HOME/sqsyiimp/yiimp_single
