#!/usr/bin/env bash

#
# This is the build option menu
#
# Author: SabiasQue.Space
#
# Updated: 2026-03-28
#

source /etc/daemonbuilder.sh
source $STORAGE_ROOT/daemon_builder/conf/info.sh

RESULT=$(dialog --stdout --title "DaemonBuilder $VERSION" --menu "Choose an option" 16 60 9 \
    ' ' "- Install coin with Berkeley autogen file -" \
    1 "Berkeley 4.8" \
    2 "Berkeley 5.1" \
    3 "Berkeley 5.3" \
    4 "Berkeley 6.2" \
    ' ' "- Other choices -" \
    5 "Install coin with makefile.unix file" \
    6 "Install coin with CMake file & DEPENDS folder" \
    7 "Install coin with UTIL folder contains BUILD.sh" \
    8 "Install precompiled coin. NEED TO BE LINUX Version!" \
    9 "Exit DaemonBuilder")

case "$RESULT" in
    1)
        clear;
        echo '
        autogen=true
        berkeley="4.8"
        ' | sudo -E tee $STORAGE_ROOT/daemon_builder/.daemon_builder.my.cnf >/dev/null 2>&1;
        source source.sh;
        ;;

    2)
        clear;
        echo '
        autogen=true
        berkeley="5.1"
        ' | sudo -E tee $STORAGE_ROOT/daemon_builder/.daemon_builder.my.cnf >/dev/null 2>&1;
        source source.sh;
        ;;

    3)
        clear;
        echo '
        autogen=true
        berkeley="5.3"
        ' | sudo -E tee $STORAGE_ROOT/daemon_builder/.daemon_builder.my.cnf >/dev/null 2>&1;
        source source.sh;
        ;;

    4)
        clear;
        echo '
        autogen=true
        berkeley="6.2"
        ' | sudo -E tee $STORAGE_ROOT/daemon_builder/.daemon_builder.my.cnf >/dev/null 2>&1;
        source source.sh;
        ;;
    5)
        clear;
        echo '
        autogen=false
        unix=true
        ' | sudo -E tee $STORAGE_ROOT/daemon_builder/.daemon_builder.my.cnf >/dev/null 2>&1;
        source source.sh;
        ;;

    6)
        clear;
        echo '
        autogen=false
        cmake=true
        ' | sudo -E tee $STORAGE_ROOT/daemon_builder/.daemon_builder.my.cnf >/dev/null 2>&1;
        source source.sh;
        ;;

    7)
        clear;
        echo '
        buildutil=true
        autogen=true
        ' | sudo -E tee $STORAGE_ROOT/daemon_builder/.daemon_builder.my.cnf >/dev/null 2>&1;
        source source.sh;
        ;;

    8)
        clear;
        echo '
        precompiled=true
        ' | sudo -E tee $STORAGE_ROOT/daemon_builder/.daemon_builder.my.cnf >/dev/null 2>&1;
        source source.sh;
        ;;

    9)
        clear;
        echo -e "$CYAN ------------------------------------------------------------------------------- $NC"
        echo -e "$YELLOW You have chosen to exit the Daemon Builder.$NC"
        echo -e "$YELLOW Type: $BLUE daemonbuilder $YELLOW anytime to start the menu again.$NC"
        echo -e "$CYAN ------------------------------------------------------------------------------- $NC"
        exit;
        ;;
esac
