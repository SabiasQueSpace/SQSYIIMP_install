# ============================================================
# SQSYIIMP - Legacy GNU Screen compatibility
# ============================================================
#
# Allows old interactive commands:
#
#   screen -r main
#   screen -r loop2
#   screen -r blocks
#   screen -r debug
#
# Managed YiiMP screens actually belong to crypto-data.
#
# All other screen commands continue using the real
# /usr/bin/screen as the current user.
# ============================================================

[[ -n "${BASH_VERSION:-}" ]] || return 0
[[ $- == *i* ]] || return 0


screen()
{
    local arg
    local managed=false

    #
    # Compatibility improvement:
    # screen -ls shows both the user's normal screens
    # and the SQSYIIMP managed screens.
    #
    if [[ "${1:-}" == "-ls" && $# -eq 1 ]]; then

        echo
        echo "=== Screens: $(id -un) ==="
        /usr/bin/screen -ls || true

        if id crypto-data >/dev/null 2>&1 &&
           [[ "$(id -un)" != "crypto-data" ]]; then

            echo
            echo "=== SQSYIIMP Screens: crypto-data ==="
            sudo -u crypto-data -H /usr/bin/screen -ls || true
        fi

        return
    fi


    #
    # Determine whether command refers to a SQSYIIMP
    # managed screen.
    #
    for arg in "$@"; do

        if [[ "$arg" =~ ^([0-9]+\.)?(main|loop2|blocks|debug)$ ]]; then
            managed=true
            break
        fi

    done


    if [[ "$managed" == "true" ]]; then

        if [[ "$(id -un)" == "crypto-data" ]]; then
            /usr/bin/screen "$@"
        else
            sudo -u crypto-data -H /usr/bin/screen "$@"
        fi

    else

        /usr/bin/screen "$@"

    fi
}
