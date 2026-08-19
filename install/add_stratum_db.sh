#!/usr/bin/env bash

##########################################
# SQSYIIMP - SabiasQue.Space
#
# Creates the MySQL stratum user and writes
# the database credentials config file for
# the new stratum server.
#
# Author: SabiasQue.Space
# Date: 2026-03-06
##########################################

source /etc/functions.sh
source $STORAGE_ROOT/yiimp/.newconf.conf

if [ -d "$HOME/sqsyiimp/yiimp_single" ]; then
  cd "$HOME/sqsyiimp/yiimp_single"
else
  cd "$HOME"
fi

print_status "Creating new stratum database user for YiiMP..."
Q1="GRANT ALL ON ${YiiMPDBName}.* TO '${StratumDBUser}'@'${StratumInternalIP}' IDENTIFIED BY '${StratumUserDBPassword}';"
Q2="FLUSH PRIVILEGES;"
SQL="${Q1}${Q2}"
sudo mariadb -u root -p"${DBRootPassword}" -e "$SQL"

print_status "Writing database credentials to .my.${generate}.cnf..."
echo '[clienthost1]
user='"${StratumDBUser}"'
password='"${StratumUserDBPassword}"'
database='"${YiiMPDBName}"'
host='"${StratumInternalIP}"'
[mysql]
user=root
password='"${DBRootPassword}"'
' | sudo -E tee "$STORAGE_ROOT/yiimp/.my.$generate.cnf" >/dev/null 2>&1
sudo chmod 0600 "$STORAGE_ROOT/yiimp/.my.$generate.cnf"

print_success "Stratum database user created successfully."
print_info "Credentials saved to: $STORAGE_ROOT/yiimp/.my.$generate.cnf"
