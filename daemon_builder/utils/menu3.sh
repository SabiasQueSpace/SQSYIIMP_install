#!/usr/bin/env bash
#####################################################
# SQSYIIMP - SabiasQue.Space
# Menu: Update new Stratum
# Updated: 2026-03-28
#####################################################

source /etc/daemonbuilder.sh
source $STORAGE_ROOT/daemon_builder/conf/info.sh

message_box " Stratum Compiler " \
"The Stratum compiler script is not yet available in this build.
\n\nCheck back later for updates."

cd ~
clear

echo -e "$CYAN --------------------------------------------------------------------------- ${NC}"
echo -e "$YELLOW    Type: $BLUE daemonbuilder $YELLOW anytime to return to the menu. ${NC}"
echo -e "$CYAN --------------------------------------------------------------------------- ${NC}"
exit
