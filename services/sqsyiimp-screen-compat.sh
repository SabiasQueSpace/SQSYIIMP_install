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
# Managed YiiMP screens belong to the configured YIIMP_USER.
#
# All other screen commands continue using the real
# /usr/bin/screen as the current user.
# ============================================================

[[ -n "${BASH_VERSION:-}" ]] || return 0
[[ $- == *i* ]] || return 0

if [[ -r /etc/default/sqsyiimp ]]; then
    # shellcheck disable=SC1091
    source /etc/default/sqsyiimp
fi

YIIMP_USER="${YIIMP_USER:-crypto-data}"


_sqsyiimp_screen_has_session()
{
    local user="$1"
    local selector="$2"
    local listing

    [[ -n "$selector" ]] || return 1

    if [[ "$user" == "$(id -un)" ]]; then
        listing="$(/usr/bin/screen -ls 2>/dev/null || true)"
    else
        listing="$(
            sudo -u "$user" -H /usr/bin/screen -ls 2>/dev/null ||
            true
        )"
    fi

    awk -v selector="$selector" '
        /^[[:space:]]*[0-9]+\./ {
            token=$1
            name=token
            sub(/^[0-9]+\./, "", name)

            if (token == selector || name == selector) {
                found=1
            }
        }

        END {
            exit(found ? 0 : 1)
        }
    ' <<< "$listing"
}


screen()
{
    local current_user
    local selector=""
    local arg
    local expect_selector=false
    local saw_attach=false
    local saw_S=false
    local saw_X=false

    current_user="$(id -un)"

    #
    # screen -ls:
    # show both the interactive user's sessions and
    # SQSYIIMP sessions owned by YIIMP_USER.
    #
    if [[ "${1:-}" == "-ls" && $# -eq 1 ]]; then

        echo
        echo "=== Screens: ${current_user} ==="
        /usr/bin/screen -ls || true

        if id "${YIIMP_USER}" >/dev/null 2>&1 &&
           [[ "$current_user" != "${YIIMP_USER}" ]]; then

            echo
            echo "=== SQSYIIMP Screens: ${YIIMP_USER} ==="
            sudo -u "${YIIMP_USER}" -H /usr/bin/screen -ls || true
        fi

        return
    fi

    #
    # When already logged in as the service user,
    # no compatibility routing is necessary.
    #
    if [[ "$current_user" == "${YIIMP_USER}" ]]; then
        /usr/bin/screen "$@"
        return
    fi

    #
    # Detect a session selector from common interactive
    # Screen commands:
    #
    #   screen -r fuec
    #   screen -r 13160.fuec
    #   screen -d -r hrc
    #   screen -x hrc
    #   screen -S hrc -X quit
    #
    for arg in "$@"; do

        if [[ "$expect_selector" == "true" ]]; then
            selector="$arg"
            expect_selector=false
            continue
        fi

        case "$arg" in

            -r|-R|-RR|-x)
                saw_attach=true
                expect_selector=true
                ;;

            -S)
                saw_S=true
                expect_selector=true
                ;;

            -X)
                saw_X=true
                ;;

        esac
    done

    #
    # Only route commands that refer to an existing session.
    #
    # Prefer a session owned by the current user if names
    # happen to collide.
    #
    if [[ -n "$selector" ]] &&
       {
           [[ "$saw_attach" == "true" ]] ||
           {
               [[ "$saw_S" == "true" ]] &&
               [[ "$saw_X" == "true" ]]
           }
       }
    then

        if _sqsyiimp_screen_has_session \
            "$current_user" "$selector"
        then
            /usr/bin/screen "$@"
            return
        fi

        if id "${YIIMP_USER}" >/dev/null 2>&1 &&
           _sqsyiimp_screen_has_session \
               "${YIIMP_USER}" "$selector"
        then

            sudo -u "${YIIMP_USER}" -H \
                /usr/bin/screen "$@"

            return
        fi
    fi

    #
    # Ordinary non-SQSYIIMP Screen command.
    #
    /usr/bin/screen "$@"
}
