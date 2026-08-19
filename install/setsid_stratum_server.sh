#!/usr/bin/env bash

##########################################
# SQSYIIMP - SabiasQue.Space
#
# Deploys and executes the stratum setup
# scripts on the remote stratum server
# via SSH using setsid and SSH_ASKPASS.
#
# Author: SabiasQue.Space
# Date: 2026-03-06
#
# Code reference:
# https://www.exratione.com/2014/08/bash-script-ssh-automation-without-a-password-prompt/
##########################################

#----------------------------------------------------------------------
# Set up values.
#----------------------------------------------------------------------
export TERM=xterm

source /etc/functions.sh
source /etc/yiimpool.conf
source "$STORAGE_ROOT/yiimp/.yiimp.conf"

# User credentials for the remote server.
StratumUser="${NewStratumUser}"
StratumPass="${NewStratumPass}"
StratumServer="${NewStratumInternalIP}"

# The scripts to run on the remote server.
script_create_user=$HOME/sqsyiimp/yiimp_single/create_user_remote.sh
script_system_stratum=$HOME/sqsyiimp/yiimp_single/remote_system_stratum_server.sh
script_stratum=$HOME/sqsyiimp/yiimp_single/remote_stratum.sh
script_motd_web=$HOME/sqsyiimp/yiimp_single/motd.sh
script_harden_web=$HOME/sqsyiimp/yiimp_single/server_harden.sh
script_ssh=$HOME/sqsyiimp/yiimp_single/ssh.sh

# Additional files to copy to the remote server.
functioncopy=$HOME/sqsyiimp/install/functions.sh
conf=${STORAGE_ROOT}/yiimp/.newconf.conf

screens=$HOME/sqsyiimp/yiimp_single/ubuntu/screens
header=$HOME/sqsyiimp/yiimp_single/ubuntu/etc/update-motd.d/00-header
sysinfo=$HOME/sqsyiimp/yiimp_single/ubuntu/etc/update-motd.d/10-sysinfo
footer=$HOME/sqsyiimp/yiimp_single/ubuntu/etc/update-motd.d/90-footer

# Desired locations of the scripts on the remote server.
remote_create_user_path='/tmp/create_user_remote.sh'
remote_system_stratum_path='/tmp/remote_system_stratum_server.sh'
remote_stratum_path='/tmp/remote_stratum.sh'
remote_motd_web_path='/tmp/motd.sh'
remote_harden_web_path='/tmp/server_harden.sh'
remote_ssh_path='/tmp/ssh.sh'

#----------------------------------------------------------------------
# Create a temp script to echo the SSH password, used by SSH_ASKPASS
#----------------------------------------------------------------------

SSH_ASKPASS_SCRIPT=/tmp/ssh-askpass-script
cat > ${SSH_ASKPASS_SCRIPT} <<EOL
#!/usr/bin/env bash
echo '${StratumPass}'
EOL
chmod u+x ${SSH_ASKPASS_SCRIPT}

#----------------------------------------------------------------------
# Set up other items needed for OpenSSH to work.
#----------------------------------------------------------------------

# Set no display, necessary for ssh to play nice with setsid and SSH_ASKPASS.
export DISPLAY=:0

# Tell SSH to read in the output of the provided script as the password.
# We still have to use setsid to eliminate access to a terminal and thus avoid
# it ignoring this and asking for a password.
export SSH_ASKPASS=${SSH_ASKPASS_SCRIPT}

# LogLevel error is to suppress the hosts warning. The others are
# necessary if working with development servers with self-signed certificates.
SSH_OPTIONS="-oLogLevel=error"
SSH_OPTIONS="${SSH_OPTIONS} -oStrictHostKeyChecking=no"
SSH_OPTIONS="${SSH_OPTIONS} -oUserKnownHostsFile=/dev/null"

#----------------------------------------------------------------------
# Run the scripts on the remote server.
#----------------------------------------------------------------------

# Load base64-encoded versions of each script.
B64_user=$(base64 --wrap=0 "${script_create_user}")
B64_system=$(base64 --wrap=0 "${script_system_stratum}")
B64_stratum=$(base64 --wrap=0 "${script_stratum}")
B64_motd=$(base64 --wrap=0 "${script_motd_web}")
B64_harden=$(base64 --wrap=0 "${script_harden_web}")
B64_ssh=$(base64 --wrap=0 "${script_ssh}")

# Build remote commands: decode base64, make executable, then execute.
system_user="base64 -d - > ${remote_create_user_path} <<< ${B64_user};"
system_user="${system_user} chmod u+x ${remote_create_user_path};"
system_user="${system_user} sh -c 'nohup ${remote_create_user_path}'"

system_stratum="base64 -d - > ${remote_system_stratum_path} <<< ${B64_system};"
system_stratum="${system_stratum} chmod u+x ${remote_system_stratum_path};"
system_stratum="${system_stratum} sh -c 'nohup ${remote_system_stratum_path}'"

stratum="base64 -d - > ${remote_stratum_path} <<< ${B64_stratum};"
stratum="${stratum} chmod u+x ${remote_stratum_path};"
stratum="${stratum} sh -c 'nohup ${remote_stratum_path}'"

motd_web="base64 -d - > ${remote_motd_web_path} <<< ${B64_motd};"
motd_web="${motd_web} chmod u+x ${remote_motd_web_path};"
motd_web="${motd_web} sh -c 'nohup ${remote_motd_web_path}'"

harden_web="base64 -d - > ${remote_harden_web_path} <<< ${B64_harden};"
harden_web="${harden_web} chmod u+x ${remote_harden_web_path};"
harden_web="${harden_web} sh -c 'nohup ${remote_harden_web_path}'"

ssh="base64 -d - > ${remote_ssh_path} <<< ${B64_ssh};"
ssh="${ssh} chmod u+x ${remote_ssh_path};"
ssh="${ssh} sh -c 'nohup ${remote_ssh_path} > /dev/null 2>&1 &'"

# Copy required files to the remote server.
print_status "Copying configuration files to remote stratum server (${StratumServer})..."
cat $functioncopy | setsid ssh ${SSH_OPTIONS} ${StratumUser}@${StratumServer} 'cat > /tmp/functions.sh'
cat $conf        | setsid ssh ${SSH_OPTIONS} ${StratumUser}@${StratumServer} 'cat > /tmp/.yiimp.conf'
cat $screens     | setsid ssh ${SSH_OPTIONS} ${StratumUser}@${StratumServer} 'cat > /tmp/screens'
cat $header      | setsid ssh ${SSH_OPTIONS} ${StratumUser}@${StratumServer} 'cat > /tmp/00-header'
cat $sysinfo     | setsid ssh ${SSH_OPTIONS} ${StratumUser}@${StratumServer} 'cat > /tmp/10-sysinfo'
cat $footer      | setsid ssh ${SSH_OPTIONS} ${StratumUser}@${StratumServer} 'cat > /tmp/90-footer'

# Execute scripts on the remote server.
print_status "Creating remote user..."
setsid ssh ${SSH_OPTIONS} ${StratumUser}@${StratumServer} "${system_user}"

print_status "Running remote system setup..."
setsid ssh ${SSH_OPTIONS} ${StratumUser}@${StratumServer} "${system_stratum}"

print_status "Building and installing stratum on remote server..."
setsid ssh ${SSH_OPTIONS} ${StratumUser}@${StratumServer} "${stratum}"

print_status "Configuring MOTD on remote server..."
setsid ssh ${SSH_OPTIONS} ${StratumUser}@${StratumServer} "${motd_web}"

print_status "Hardening remote server..."
setsid ssh ${SSH_OPTIONS} ${StratumUser}@${StratumServer} "${harden_web}"

print_status "Configuring SSH on remote server..."
setsid ssh ${SSH_OPTIONS} ${StratumUser}@${StratumServer} "${ssh}"

print_success "Remote stratum server deployment complete."
print_info "Remote server: ${StratumServer}"
