#!/usr/bin/env bash

############################################################
# SQSYIIMP - YiiMP repository selector
# SabiasQue.Space
############################################################

# Repository list
githubyiimptpruvot="https://github.com/tpruvot/yiimp.git"
githubrepoKudaraidee="https://github.com/Kudaraidee/yiimp.git"
githubrepoAfinielTech="https://github.com/Afiniel-tech/yiimp.git"
githubrepoAfiniel="https://github.com/afiniel/yiimp.git"
githubrepoSabiasQue="https://github.com/SabiasQueSpace/yiimp.git"
githubrepoTpfuemp="https://github.com/tpfuemp/yiimp.git"


set_yiimp_repository()
{
    local choice="$1"

    case "$choice" in

        1)
            YIIMP_REPO_ID="1"
            YIIMP_REPO_NAME="Kudaraidee"
            YiiMPRepo="$githubrepoKudaraidee"
            ;;

        2)
            YIIMP_REPO_ID="2"
            YIIMP_REPO_NAME="tpruvot"
            YiiMPRepo="$githubyiimptpruvot"
            ;;

        3)
            YIIMP_REPO_ID="3"
            YIIMP_REPO_NAME="Afiniel-Tech"
            YiiMPRepo="$githubrepoAfinielTech"
            ;;

        4)
            YIIMP_REPO_ID="4"
            YIIMP_REPO_NAME="Afiniel"
            YiiMPRepo="$githubrepoAfiniel"
            ;;

        5)
            YIIMP_REPO_ID="5"
            YIIMP_REPO_NAME="SabiasQueSpace"
            YiiMPRepo="$githubrepoSabiasQue"
            ;;

        6)
            YIIMP_REPO_ID="6"
            YIIMP_REPO_NAME="tpfuemp"
            YiiMPRepo="$githubrepoTpfuemp"
            ;;

        *)
            return 1
            ;;
    esac

    export YIIMP_REPO_ID
    export YIIMP_REPO_NAME
    export YiiMPRepo

    return 0
}


verify_yiimp_repository()
{
    local repo="$1"

    echo
    echo "Checking repository:"
    echo "  $repo"
    echo

    if git ls-remote "$repo" HEAD >/dev/null 2>&1; then
        echo "SUCCESS: repository is accessible"
        return 0
    fi

    echo "ERROR: repository is not accessible:"
    echo "       $repo"

    return 1
}


select_yiimp_repository()
{
    local choice

    while true
    do

        if command -v dialog >/dev/null 2>&1; then

            choice="$(
                dialog \
                --stdout \
                --backtitle "SQSYIIMP v1 • SabiasQue.Space" \
                --title "Select YiiMP repository" \
                --default-item "5" \
                --menu \
                "Select the YiiMP source repository to install:" \
                20 84 10 \
                1 "Kudaraidee    - github.com/Kudaraidee/yiimp" \
                2 "tpruvot       - github.com/tpruvot/yiimp" \
                3 "Afiniel-Tech  - github.com/Afiniel-tech/yiimp" \
                4 "Afiniel       - github.com/afiniel/yiimp" \
                5 "SabiasQueSpace - github.com/SabiasQueSpace/yiimp [DEFAULT]" \
                6 "tpfuemp       - github.com/tpfuemp/yiimp"
            )"

            # Cancel => use our repository.
            choice="${choice:-5}"

        else

            echo
            echo "============================================================"
            echo "              Select YiiMP Repository"
            echo "============================================================"
            echo
            echo "  1. Kudaraidee"
            echo "     $githubrepoKudaraidee"
            echo
            echo "  2. tpruvot"
            echo "     $githubyiimptpruvot"
            echo
            echo "  3. Afiniel-Tech"
            echo "     $githubrepoAfinielTech"
            echo
            echo "  4. Afiniel"
            echo "     $githubrepoAfiniel"
            echo
            echo "  5. SabiasQueSpace [DEFAULT]"
            echo "     $githubrepoSabiasQue"
            echo
            echo "  6. tpfuemp"
            echo "     $githubrepoTpfuemp"
            echo
            echo "============================================================"
            echo

            read -r -p "Select repository [5]: " choice

            choice="${choice:-5}"

        fi


        if ! [[ "$choice" =~ ^[1-6]$ ]]; then
            echo "ERROR: select a number from 1 to 6"
            continue
        fi


        set_yiimp_repository "$choice" || continue


        echo
        echo "Selected YiiMP repository:"
        echo
        echo "  ID   : $YIIMP_REPO_ID"
        echo "  Name : $YIIMP_REPO_NAME"
        echo "  URL  : $YiiMPRepo"
        echo


        if verify_yiimp_repository "$YiiMPRepo"; then
            return 0
        fi


        echo
        echo "Select another repository."
        echo

    done
}


persist_yiimp_repository()
{
    local conf="${1:-${STORAGE_ROOT:-/home/${STORAGE_USER:-crypto-data}}/yiimp/.yiimp.conf}"

    if [[ ! -f "$conf" ]]; then
        echo "WARNING: YiiMP config not found yet:"
        echo "         $conf"
        return 0
    fi

    #
    # Remove any previous repository configuration,
    # including the old hard-coded Kudaraidee entry.
    #
    sudo sed -i \
        -e '/^[[:space:]]*YIIMP_REPO_ID=/d' \
        -e '/^[[:space:]]*YIIMP_REPO_NAME=/d' \
        -e '/^[[:space:]]*YiiMPRepo=/d' \
        "$conf"

    {
        echo
        printf "YIIMP_REPO_ID='%s'\n" "$YIIMP_REPO_ID"
        printf "YIIMP_REPO_NAME='%s'\n" "$YIIMP_REPO_NAME"
        printf "YiiMPRepo='%s'\n" "$YiiMPRepo"
    } | sudo tee -a "$conf" >/dev/null

    echo
    echo "YiiMP repository saved:"
    echo "  $conf"
    echo
    echo "  YIIMP_REPO_ID=$YIIMP_REPO_ID"
    echo "  YIIMP_REPO_NAME=$YIIMP_REPO_NAME"
    echo "  YiiMPRepo=$YiiMPRepo"
}


load_yiimp_repository()
{
    local conf="${1:-${STORAGE_ROOT:-/home/${STORAGE_USER:-crypto-data}}/yiimp/.yiimp.conf}"

    if [[ -r "$conf" ]]; then
        # shellcheck disable=SC1090
        source "$conf"

        if [[ -n "${YiiMPRepo:-}" ]]; then
            export YiiMPRepo
            export YIIMP_REPO_ID
            export YIIMP_REPO_NAME
            return 0
        fi
    fi

    return 1
}
