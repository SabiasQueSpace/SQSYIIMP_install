#!/usr/bin/env bash


# === MHP CANONICAL COIN BINARIES ===
#
# The package may provide:
#
#   ravend
#   raven-cli
#
# but MegaHashPool/YiiMP uses the full canonical coin name:
#
#   ravencoind
#   ravencoin-cli
#
# The original names are retained as compatibility symlinks.
#

mhp_normalize_coin_name()
{
    local raw="${1:-}"

    printf '%s' "$raw" \
        | tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9]//g'
}


mhp_canonical_binary_name()
{
    local role="$1"
    local base

    base="$(mhp_normalize_coin_name "${coin:-}")"

    if [[ -z "$base" ]]; then
        echo "ERROR: Unable to determine canonical coin name" >&2
        return 1
    fi

    case "$role" in
        daemon)
            printf '%sd' "$base"
            ;;

        cli)
            printf '%s-cli' "$base"
            ;;

        tx)
            printf '%s-tx' "$base"
            ;;

        util)
            printf '%s-util' "$base"
            ;;

        hash)
            printf '%s-hash' "$base"
            ;;

        wallet)
            printf '%s-wallet' "$base"
            ;;

        qt)
            printf '%s-qt' "$base"
            ;;

        *)
            echo "ERROR: Unknown binary role: $role" >&2
            return 1
            ;;
    esac
}


mhp_install_coin_binary()
{
    local source_file="$1"
    local original_name="$2"
    local role="$3"

    local canonical_name
    local canonical_path
    local original_path

    if [[ -z "$original_name" ]]; then
        echo "ERROR: Empty original binary name for role $role"
        return 1
    fi

    if [[ ! -f "$source_file" ]]; then
        echo "ERROR: Binary source not found:"
        echo "       $source_file"
        return 1
    fi

    canonical_name="$(mhp_canonical_binary_name "$role")" || return 1

    canonical_path="/usr/bin/${canonical_name}"
    original_path="/usr/bin/${original_name}"

    echo
    echo "INFO: Installing coin binary"
    echo "INFO: Role           : $role"
    echo "INFO: Package binary : $original_name"
    echo "INFO: Canonical name : $canonical_name"
    echo "INFO: Destination    : $canonical_path"

    sudo install \
        -o root \
        -g root \
        -m 755 \
        "$source_file" \
        "$canonical_path" || return 1

    #
    # Preserve original package name as compatibility alias.
    #
    # Example:
    #
    #   /usr/bin/ravend -> /usr/bin/ravencoind
    #   /usr/bin/raven-cli -> /usr/bin/ravencoin-cli
    #
    if [[ "$original_name" != "$canonical_name" ]]; then

        sudo rm -f "$original_path"

        sudo ln -s \
            "$canonical_path" \
            "$original_path" || return 1

        echo "INFO: Compatibility : $original_path -> $canonical_path"
    fi

    #
    # Caller uses this to update coind/coincli/etc.
    #
    MHP_INSTALLED_BINARY="$canonical_name"

    echo "SUCCESS: Installed /usr/bin/$canonical_name"

    return 0
}

# === END MHP CANONICAL COIN BINARIES ===

# === MHP SAFE DAEMON SHUTDOWN ================================================

mhp_resolve_daemon_path()
{
    local daemon_name="${1:-}"
    local path="/usr/bin/${daemon_name}"

    if [[ -e "$path" || -L "$path" ]]; then
        readlink -f "$path" 2>/dev/null || printf '%s\n' "$path"
    else
        printf '%s\n' "$path"
    fi
}

mhp_pid_is_daemon()
{
    local pid="${1:-}"
    local daemon_name="${2:-}"
    local expected_path=""
    local exe=""

    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    [[ -e "/proc/${pid}" ]] || return 1

    expected_path="$(mhp_resolve_daemon_path "$daemon_name")"

    exe="$(sudo readlink -f "/proc/${pid}/exe" 2>/dev/null || true)"
    exe="${exe% (deleted)}"

    [[ -n "$exe" && "$exe" == "$expected_path" ]]
}

mhp_find_daemon_pids()
{
    local daemon_name="${1:-}"
    local expected_path=""
    local proc=""
    local pid=""
    local exe=""

    expected_path="$(mhp_resolve_daemon_path "$daemon_name")"

    for proc in /proc/[0-9]*; do
        [[ -e "$proc" ]] || continue

        pid="${proc##*/}"

        exe="$(sudo readlink -f "$proc/exe" 2>/dev/null || true)"
        exe="${exe% (deleted)}"

        [[ -n "$exe" && "$exe" == "$expected_path" ]] || continue

        printf '%s\n' "$pid"
    done
}

mhp_check_datadir_locks()
{
    local datadir="${1:-}"
    local lock=""
    local holders=""
    local found=0

    [[ -n "$datadir" && -d "$datadir" ]] || return 0

    # fuser is used only to determine whether a lock is actively held.
    # Lock files themselves are NEVER deleted here.
    command -v fuser >/dev/null 2>&1 || return 0

    for lock in \
        "$datadir/.lock" \
        "$datadir/chainstate/LOCK" \
        "$datadir/blocks/index/LOCK"
    do
        [[ -e "$lock" ]] || continue

        holders="$(sudo fuser "$lock" 2>/dev/null || true)"

        if [[ -n "$holders" ]]; then
            print_error "Lock still held: $lock"
            print_error "Process(es): $holders"
            found=1
        fi
    done

    [[ "$found" -eq 0 ]]
}

mhp_wait_for_daemon_shutdown()
{
    local daemon_pids="${1:-}"
    local daemon_name="${2:-}"
    local datadir="${3:-}"
    local timeout="${4:-1800}"

    local elapsed=0
    local pid=""
    local alive=0
    local current_pids=""

    [[ -z "${daemon_pids// }" ]] && return 0

    print_status "Waiting for ${daemon_name} to shut down cleanly..."

    while (( elapsed < timeout )); do
        alive=0

        for pid in $daemon_pids; do
            if mhp_pid_is_daemon "$pid" "$daemon_name"; then
                alive=1
                break
            fi
        done

        (( alive == 0 )) && break

        if (( elapsed % 10 == 0 )); then
            echo -ne \
                "${GREEN}  Waiting for ${YELLOW}${daemon_name}${GREEN} shutdown: ${CYAN}${elapsed}s${NC}\033[0K\r"
        fi

        sleep 2
        elapsed=$((elapsed + 2))
    done

    echo

    if (( alive != 0 )); then
        print_error "${daemon_name} did not stop within ${timeout} seconds"
        print_error "Binary replacement aborted to protect the blockchain database"
        return 1
    fi

    # Make sure the daemon was not automatically restarted with another PID.
    current_pids="$(mhp_find_daemon_pids "$daemon_name" | tr '\n' ' ')"

    if [[ -n "${current_pids// }" ]]; then
        print_error \
            "${daemon_name} is still/re-again running (PID(s): ${current_pids})"

        print_error "Binary replacement aborted"
        return 1
    fi

    if ! mhp_check_datadir_locks "$datadir"; then
        print_error "Database lock still active in ${datadir}"
        print_error "Binary replacement aborted"
        return 1
    fi

    print_success \
        "${daemon_name} stopped cleanly after ${elapsed} seconds"

    return 0
}

# === END MHP SAFE DAEMON SHUTDOWN ============================================



#
# This is the option update coin daemon menu
#
# Author: SabiasQue.Space
#
# Updated: 2026-03-28
#

source /etc/daemonbuilder.sh
source /etc/functions.sh
source $STORAGE_ROOT/daemon_builder/.daemon_builder.my.cnf
source $STORAGE_ROOT/daemon_builder/conf/info.sh

YIIMPOLL=/etc/yiimpool.conf
if [[ -f "$YIIMPOLL" ]]; then
    source /etc/yiimpool.conf
    YIIMPCONF=true
fi
CREATECOIN=false

now=$(date +"%m_%d_%Y")

MIN_CPUS_FOR_COMPILATION=3

if ! NPROC=$(nproc); then
    print_error "nproc command not found. Failed to run."
    exit 1
fi

if [[ "$NPROC" -le "$MIN_CPUS_FOR_COMPILATION" ]]; then
    NPROC=1
else
    NPROC=$((NPROC - 2))
fi

print_header "Setting Up Build Environment"
print_status "Creating temporary build directory..."

source $STORAGE_ROOT/daemon_builder/.daemon_builder.my.cnf

if [[ ! -e "$STORAGE_ROOT/daemon_builder/temp_coin_builds" ]]; then
    sudo mkdir -p $STORAGE_ROOT/daemon_builder/temp_coin_builds
    print_success "Created temp_coin_builds directory"
else
    sudo rm -rf $STORAGE_ROOT/daemon_builder/temp_coin_builds/*
    print_info "Cleaned existing temp_coin_builds directory"
fi

sudo setfacl -m u:${USERSERVER}:rwx $STORAGE_ROOT/daemon_builder/temp_coin_builds
cd $STORAGE_ROOT/daemon_builder/temp_coin_builds

print_header "Coin Configuration"

input_box "Coin Information" \
"Please enter the Coin Symbol. Example: BTC
\n\n*To paste, use Ctrl+Shift+V (or right-click in some terminals).
\n\nCoin Name:" \
"" \
coin

if [[ ("${precompiled}" == "true") ]]; then
    input_box "Precompiled Binary Information" \
    "Please enter the URL link to the precompiled compressed file.
    \n\nExample: bitcoin-0.16.3-x86_64-linux-gnu.tar.gz
    \n\nSupported formats: .tar.gz, .zip, .7z
    \n\n*To paste, use Ctrl+Shift+V (or right-click in some terminals).
    \n\nPrecompiled Binary URL:" \
    "" \
    coin_precompiled
else
    print_header "Source Code"

    input_box "GitHub Repository" \
    "Please enter the GitHub repository link.
    \n\nExample: https://github.com/example-repo-name/coin-wallet.git
    \n\n*To paste, use Ctrl+Shift+V (or right-click in some terminals).
    \n\nGitHub Repository Link:" \
    "" \
    git_hub

    dialog --title "Development Branch Selection" \
    --yesno "Would you like to use the development branch instead of main?\n\nSelect Yes to use the development branch." 8 60
    response=$?
    case $response in
        0)
            swithdevelop=yes
            print_info "Using development branch"
            ;;
        1)
            swithdevelop=no
            print_info "Using main branch"
            ;;
        255)
            print_warning "ESC key pressed - defaulting to main branch"
            swithdevelop=no
            ;;
    esac

    if [[ ("${swithdevelop}" == "no") ]]; then
        dialog --title "Branch Selection" \
        --yesno "Would you like to use a specific branch?\n\nSelect Yes to specify a particular version." 8 60
        response=$?
        case $response in
            0)
                branch_git_hub=yes
                print_info "Will prompt for specific branch"
                ;;
            1)
                branch_git_hub=no
                print_info "Using default branch"
                ;;
            255)
                print_warning "ESC key pressed - using default branch"
                branch_git_hub=no
                ;;
        esac

        if [[ ("${branch_git_hub}" == "yes") ]]; then
            input_box "Git Branch Selection" \
            "Please enter the branch name to use.
            \n\nExample: v1.2.3 or feature/new-update
            \n\n*To paste, use Ctrl+Shift+V (or right-click in some terminals).
            \n\nBranch name:" \
            "" \
            branch_git_hub_ver

            print_info "Selected branch: ${branch_git_hub_ver}"
        fi
    fi
fi

clear
print_divider

set -e
print_header "Starting Update: ${coin^^}"

coindir=$coin$now

echo '
lastcoin='"${coindir}"'
' | sudo -E tee $STORAGE_ROOT/daemon_builder/temp_coin_builds/.lastcoin.conf >/dev/null 2>&1

if [[ ! -e $coindir ]]; then
    if [[ ("$precompiled" == "true") ]]; then
        print_status "Downloading precompiled binary..."
        mkdir $coindir
        cd "${coindir}"
        sudo wget $coin_precompiled
        print_success "Downloaded precompiled binary"
    else
        print_status "Cloning repository..."
        git clone $git_hub $coindir
        cd "${coindir}"
        print_success "Repository cloned successfully"

        if [[ ("${branch_git_hub}" == "yes") ]]; then
            print_status "Checking out branch: ${branch_git_hub_ver}..."
            git fetch
            git checkout "$branch_git_hub_ver"
            print_success "Switched to branch: ${branch_git_hub_ver}"
        fi

        if [[ ("${swithdevelop}" == "yes") ]]; then
            print_status "Switching to development branch..."
            git checkout develop
            print_success "Switched to development branch"
        fi
    fi
    errorexist="false"
else
    print_error "${coindir} already exists in temp folder"
    print_info "If there was an error in the build use the build error options on the installer"
    errorexist="true"
    exit 0
fi

if [[ ("${errorexist}" == "false") ]]; then
    print_status "Setting permissions for build directory..."
    sudo chmod -R 777 $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}
    sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type d -exec chmod 755 {} \;
    sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type f -exec chmod 755 {} \;
    print_success "Permissions set successfully"
fi

if [[ ("$autogen" == "true") ]]; then

    # Build the coin under berkeley 4.8
    if [[ ("$berkeley" == "4.8") ]]; then
        print_header "Building ${coin^^} with Berkeley DB 4.8"

        basedir=$(pwd)

        FILEAUTOGEN=$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/autogen.sh
        if [[ ! -f "$FILEAUTOGEN" ]]; then
            print_warning "autogen.sh not found in root directory"
            print_info "Available directories:"
            echo -e "${YELLOW}"
            find . -maxdepth 1 -type d \( -perm -1 -o \( -perm -10 -o -perm -100 \) \) -printf "%f\n"
            echo -e "${NC}"

            read -r -e -p "Enter the installation folder name (e.g. bitcoin): " repotherinstall

            print_status "Moving files to build directory..."
            sudo mv $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/${repotherinstall}/* $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}
            print_success "Files moved successfully"
        fi

        print_status "Running autogen.sh..."
        sh autogen.sh
        print_success "autogen.sh completed"

        if [[ ! -e "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/share/genbuild.sh" ]]; then
            print_info "genbuild.sh not found - skipping"
        else
            sudo chmod 755 $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/share/genbuild.sh
        fi

        if [[ ! -e "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/leveldb/build_detect_platform" ]]; then
            print_info "build_detect_platform not found - skipping"
        else
            sudo chmod 755 $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/leveldb/build_detect_platform
        fi

        print_status "Configuring build..."
        sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type d -exec chmod 755 {} \;
        sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type f -exec chmod 755 {} \;

        ./configure CPPFLAGS="-I$STORAGE_ROOT/daemon_builder/berkeley/db4/include -O2" LDFLAGS="-L$STORAGE_ROOT/daemon_builder/berkeley/db4/lib" --with-incompatible-bdb --without-gui --disable-tests
        print_success "Configuration completed"

        print_status "Building ${coin^^}..."
        sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type d -exec chmod 755 {} \;
        sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type f -exec chmod 755 {} \;

        TMP=$(mktemp)
        print_status "Running make with ${NPROC} cores..."
        make -j${NPROC} 2>&1 | tee $TMP

        if [ ${PIPESTATUS[0]} -eq 0 ]; then
            print_success "Build completed successfully"
        else
            print_error "Build failed - check the error log"
            cat $TMP
            rm $TMP
            exit 1
        fi
        rm $TMP
    fi

    # Build the coin under berkeley 5.1
    if [[ ("$berkeley" == "5.1") ]]; then
        print_header "Building ${coin^^} with Berkeley DB 5.1"

        basedir=$(pwd)

        FILEAUTOGEN=$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/autogen.sh
        if [[ ! -f "$FILEAUTOGEN" ]]; then
            print_warning "autogen.sh not found in root directory"
            print_info "Available directories:"
            echo -e "${YELLOW}"
            find . -maxdepth 1 -type d \( -perm -1 -o \( -perm -10 -o -perm -100 \) \) -printf "%f\n"
            echo -e "${NC}"

            read -r -e -p "Enter the installation folder name (e.g. bitcoin): " repotherinstall

            print_status "Moving files to build directory..."
            sudo mv $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/${repotherinstall}/* $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}
            print_success "Files moved successfully"
        fi

        print_status "Running autogen.sh..."
        sh autogen.sh
        print_success "autogen.sh completed"

        if [[ ! -e "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/share/genbuild.sh" ]]; then
            print_info "genbuild.sh not found - skipping"
        else
            sudo chmod 755 $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/share/genbuild.sh
        fi

        if [[ ! -e "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/leveldb/build_detect_platform" ]]; then
            print_info "build_detect_platform not found - skipping"
        else
            sudo chmod 755 $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/leveldb/build_detect_platform
        fi

        print_status "Configuring build..."
        sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type d -exec chmod 755 {} \;
        sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type f -exec chmod 755 {} \;

        ./configure CPPFLAGS="-I$STORAGE_ROOT/daemon_builder/berkeley/db5/include -O2" LDFLAGS="-L$STORAGE_ROOT/daemon_builder/berkeley/db5/lib" --with-incompatible-bdb --without-gui --disable-tests
        print_success "Configuration completed"

        print_status "Building ${coin^^}..."
        sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type d -exec chmod 755 {} \;
        sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type f -exec chmod 755 {} \;

        TMP=$(mktemp)
        print_status "Running make with ${NPROC} cores..."
        make -j${NPROC} 2>&1 | tee $TMP

        if [ ${PIPESTATUS[0]} -eq 0 ]; then
            print_success "Build completed successfully"
        else
            print_error "Build failed - check the error log"
            cat $TMP
            rm $TMP
            exit 1
        fi
        rm $TMP
    fi

    # Build the coin under berkeley 5.3
    if [[ ("$berkeley" == "5.3") ]]; then
        print_header "Building ${coin^^} with Berkeley DB 5.3"

        basedir=$(pwd)

        FILEAUTOGEN=$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/autogen.sh
        if [[ ! -f "$FILEAUTOGEN" ]]; then
            print_warning "autogen.sh not found in root directory"
            print_info "Available directories:"
            echo -e "${YELLOW}"
            find . -maxdepth 1 -type d \( -perm -1 -o \( -perm -10 -o -perm -100 \) \) -printf "%f\n"
            echo -e "${NC}"

            read -r -e -p "Enter the installation folder name (e.g. bitcoin): " repotherinstall

            print_status "Moving files to build directory..."
            sudo mv $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/${repotherinstall}/* $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}
            print_success "Files moved successfully"
        fi

        print_status "Running autogen.sh..."
        sh autogen.sh
        print_success "autogen.sh completed"

        if [[ ! -e "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/share/genbuild.sh" ]]; then
            print_info "genbuild.sh not found - skipping"
        else
            sudo chmod 755 $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/share/genbuild.sh
        fi

        if [[ ! -e "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/leveldb/build_detect_platform" ]]; then
            print_info "build_detect_platform not found - skipping"
        else
            sudo chmod 755 $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/leveldb/build_detect_platform
        fi

        print_status "Configuring build..."
        sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type d -exec chmod 755 {} \;
        sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type f -exec chmod 755 {} \;

        ./configure CPPFLAGS="-I$STORAGE_ROOT/daemon_builder/berkeley/db5.3/include -O2" LDFLAGS="-L$STORAGE_ROOT/daemon_builder/berkeley/db5.3/lib" --with-incompatible-bdb --without-gui --disable-tests
        print_success "Configuration completed"

        print_status "Building ${coin^^}..."
        sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type d -exec chmod 755 {} \;
        sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type f -exec chmod 755 {} \;

        TMP=$(mktemp)
        print_status "Running make with ${NPROC} cores..."
        make -j${NPROC} 2>&1 | tee $TMP

        if [ ${PIPESTATUS[0]} -eq 0 ]; then
            print_success "Build completed successfully"
        else
            print_error "Build failed - check the error log"
            cat $TMP
            rm $TMP
            exit 1
        fi
        rm $TMP
    fi

    # Build the coin under berkeley 6.2
    if [[ ("$berkeley" == "6.2") ]]; then
        print_header "Building ${coin^^} with Berkeley DB 6.2"

        basedir=$(pwd)

        FILEAUTOGEN=$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/autogen.sh
        if [[ ! -f "$FILEAUTOGEN" ]]; then
            print_warning "autogen.sh not found in root directory"
            print_info "Available directories:"
            echo -e "${YELLOW}"
            find . -maxdepth 1 -type d \( -perm -1 -o \( -perm -10 -o -perm -100 \) \) -printf "%f\n"
            echo -e "${NC}"

            read -r -e -p "Enter the installation folder name (e.g. bitcoin): " repotherinstall

            print_status "Moving files to build directory..."
            sudo mv $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/${repotherinstall}/* $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}
            print_success "Files moved successfully"
        fi

        print_status "Running autogen.sh..."
        sh autogen.sh
        print_success "autogen.sh completed"

        if [[ ! -e "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/share/genbuild.sh" ]]; then
            print_info "genbuild.sh not found - skipping"
        else
            sudo chmod 755 $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/share/genbuild.sh
        fi

        if [[ ! -e "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/leveldb/build_detect_platform" ]]; then
            print_info "build_detect_platform not found - skipping"
        else
            sudo chmod 755 $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/leveldb/build_detect_platform
        fi

        print_status "Configuring build..."
        sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type d -exec chmod 755 {} \;
        sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type f -exec chmod 755 {} \;

        ./configure CPPFLAGS="-I$STORAGE_ROOT/daemon_builder/berkeley/db6.2/include -O2" LDFLAGS="-L$STORAGE_ROOT/daemon_builder/berkeley/db6.2/lib" --with-incompatible-bdb --without-gui --disable-tests
        print_success "Configuration completed"

        print_status "Building ${coin^^}..."
        sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type d -exec chmod 755 {} \;
        sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type f -exec chmod 755 {} \;

        TMP=$(mktemp)
        print_status "Running make with ${NPROC} cores..."
        make -j${NPROC} 2>&1 | tee $TMP

        if [ ${PIPESTATUS[0]} -eq 0 ]; then
            print_success "Build completed successfully"
        else
            print_error "Build failed - check the error log"
            cat $TMP
            rm $TMP
            exit 1
        fi
        rm $TMP
    fi

    # Build the coin under UTIL directory with BUILD.SH file
    if [[ ("$buildutil" == "true") ]]; then
        print_header "Building ${coin^^} using UTIL directory with BUILD.SH"

        basedir=$(pwd)

        FILEAUTOGEN=$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/autogen.sh
        if [[ ! -f "$FILEAUTOGEN" ]]; then
            print_warning "autogen.sh not found in root directory"
            print_info "Available directories:"
            echo -e "${YELLOW}"
            find . -maxdepth 1 -type d \( -perm -1 -o \( -perm -10 -o -perm -100 \) \) -printf "%f\n"
            echo -e "${NC}"

            read -r -e -p "Enter the installation folder name (e.g. bitcoin): " repotherinstall

            print_status "Moving files to build directory..."
            sudo mv $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/${repotherinstall}/* $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}
            print_success "Files moved successfully"
        fi

        print_status "Running autogen.sh..."
        sh autogen.sh
        print_success "autogen.sh completed"

        print_info "Available directories:"
        find . -maxdepth 1 -type d \( -perm -1 -o \( -perm -10 -o -perm -100 \) \) -printf "%f\n"
        read -r -e -p "Enter the folder containing BUILD.SH (e.g. xxutil): " reputil
        cd $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/${reputil}
        print_info "Build directory: $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/${reputil}"
        sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type d -exec chmod 755 {} \;
        sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type f -exec chmod 755 {} \;

        print_status "Running build.sh..."
        bash build.sh -j$(nproc)
        print_success "build.sh completed"

        if [[ ! -e "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/${reputil}/fetch-params.sh" ]]; then
            print_info "fetch-params.sh not found - skipping"
        else
            sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type d -exec chmod 755 {} \;
            sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type f -exec chmod 755 {} \;
            print_status "Running fetch-params.sh..."
            sh fetch-params.sh
            print_success "fetch-params.sh completed"
        fi
    fi

else

    # Build the coin under cmake
    if [[ ("$cmake" == "true") ]]; then
        clear
        DEPENDS="$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/depends"

        if [ -d "$DEPENDS" ]; then
            print_header "Building ${coin^^} using CMake with DEPENDS directory"

            read -r -e -p "Hide build LOG output? [y/N]: " ifhidework

            print_status "Executing make on depends directory..."
            cd $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/depends
            if [[ ("$ifhidework" == "y" || "$ifhidework" == "Y") ]]; then
                TMP=$(mktemp)
                hide_output make -j${NPROC} 2>&1 | tee $TMP
                if [ ${PIPESTATUS[0]} -ne 0 ]; then
                    print_error "Depends build failed - check the error log"
                    rm $TMP
                    exit 1
                fi
                rm $TMP
            else
                sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type d -exec chmod 755 {} \;
                sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type f -exec chmod 755 {} \;
                TMP=$(mktemp)
                make -j${NPROC} 2>&1 | tee $TMP
                if [ ${PIPESTATUS[0]} -ne 0 ]; then
                    print_error "Depends build failed - check the error log"
                    rm $TMP
                    exit 1
                fi
                rm $TMP
            fi
            print_success "Depends build completed"

            print_status "Running autogen.sh..."
            cd $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}
            if [[ ("$ifhidework" == "y" || "$ifhidework" == "Y") ]]; then
                hide_output sh autogen.sh
            else
                sh autogen.sh
            fi
            print_success "autogen.sh completed"

            # Configure with detected platform
            sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type d -exec chmod 755 {} \;
            sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type f -exec chmod 755 {} \;

            if [ -d "$DEPENDS/i686-pc-linux-gnu" ]; then
                print_status "Configuring with i686-pc-linux-gnu..."
                if [[ ("$ifhidework" == "y" || "$ifhidework" == "Y") ]]; then
                    hide_output ./configure --with-incompatible-bdb --prefix=`pwd`/depends/i686-pc-linux-gnu
                else
                    ./configure --with-incompatible-bdb --prefix=`pwd`/depends/i686-pc-linux-gnu
                fi
            elif [ -d "$DEPENDS/x86_64-pc-linux-gnu/" ]; then
                print_status "Configuring with x86_64-pc-linux-gnu..."
                if [[ ("$ifhidework" == "y" || "$ifhidework" == "Y") ]]; then
                    hide_output ./configure --with-incompatible-bdb --prefix=`pwd`/depends/x86_64-pc-linux-gnu
                else
                    ./configure --with-incompatible-bdb --prefix=`pwd`/depends/x86_64-pc-linux-gnu
                fi
            elif [ -d "$DEPENDS/i686-w64-mingw32/" ]; then
                print_status "Configuring with i686-w64-mingw32..."
                if [[ ("$ifhidework" == "y" || "$ifhidework" == "Y") ]]; then
                    hide_output ./configure --with-incompatible-bdb --prefix=`pwd`/depends/i686-w64-mingw32
                else
                    ./configure --with-incompatible-bdb --prefix=`pwd`/depends/i686-w64-mingw32
                fi
            elif [ -d "$DEPENDS/x86_64-w64-mingw32/" ]; then
                print_status "Configuring with x86_64-w64-mingw32..."
                if [[ ("$ifhidework" == "y" || "$ifhidework" == "Y") ]]; then
                    hide_output ./configure --with-incompatible-bdb --prefix=`pwd`/depends/x86_64-w64-mingw32
                else
                    ./configure --with-incompatible-bdb --prefix=`pwd`/depends/x86_64-w64-mingw32
                fi
            elif [ -d "$DEPENDS/x86_64-apple-darwin14/" ]; then
                print_status "Configuring with x86_64-apple-darwin14..."
                if [[ ("$ifhidework" == "y" || "$ifhidework" == "Y") ]]; then
                    hide_output ./configure --with-incompatible-bdb --prefix=`pwd`/depends/x86_64-apple-darwin14
                else
                    ./configure --with-incompatible-bdb --prefix=`pwd`/depends/x86_64-apple-darwin14
                fi
            elif [ -d "$DEPENDS/arm-linux-gnueabihf/" ]; then
                print_status "Configuring with arm-linux-gnueabihf..."
                if [[ ("$ifhidework" == "y" || "$ifhidework" == "Y") ]]; then
                    hide_output ./configure --with-incompatible-bdb --prefix=`pwd`/depends/arm-linux-gnueabihf
                else
                    ./configure --with-incompatible-bdb --prefix=`pwd`/depends/arm-linux-gnueabihf
                fi
            elif [ -d "$DEPENDS/aarch64-linux-gnu/" ]; then
                print_status "Configuring with aarch64-linux-gnu..."
                if [[ ("$ifhidework" == "y" || "$ifhidework" == "Y") ]]; then
                    hide_output ./configure --with-incompatible-bdb --prefix=`pwd`/depends/aarch64-linux-gnu
                else
                    ./configure --with-incompatible-bdb --prefix=`pwd`/depends/aarch64-linux-gnu
                fi
            fi
            print_success "Configuration completed"

            print_status "Running final make with ${NPROC} cores..."
            sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type d -exec chmod 755 {} \;
            sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type f -exec chmod 755 {} \;

            if [[ ("$ifhidework" == "y" || "$ifhidework" == "Y") ]]; then
                TMP=$(mktemp)
                hide_output make -j${NPROC} 2>&1 | tee $TMP
                if [ ${PIPESTATUS[0]} -ne 0 ]; then
                    print_error "Build failed - check the error log"
                    rm $TMP
                    exit 1
                fi
                rm $TMP
            else
                TMP=$(mktemp)
                make -j${NPROC} 2>&1 | tee $TMP
                if [ ${PIPESTATUS[0]} -ne 0 ]; then
                    print_error "Build failed - check the error log"
                    rm $TMP
                    exit 1
                fi
                rm $TMP
            fi
            print_success "Build completed successfully"
        else
            print_header "Building ${coin^^} using CMake method"

            print_status "Initializing git submodules..."
            cd $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir} && git submodule init && git submodule update
            print_success "Submodules initialized"

            print_status "Running make with ${NPROC} cores..."
            sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type d -exec chmod 755 {} \;
            sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type f -exec chmod 755 {} \;

            TMP=$(mktemp)
            make -j${NPROC} 2>&1 | tee $TMP
            if [ ${PIPESTATUS[0]} -eq 0 ]; then
                print_success "Build completed successfully"
            else
                print_error "Build failed - check the error log"
                cat $TMP
                rm $TMP
                exit 1
            fi
            rm $TMP
        fi
    fi

    # Build the coin under unix
    if [[ ("$unix" == "true") ]]; then
        print_header "Building ${coin^^} using makefile.unix method"

        cd $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src

        if [[ ! -e "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/obj" ]]; then
            mkdir -p $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/obj
            print_info "Created src/obj directory"
        else
            print_info "src/obj directory already exists"
        fi

        if [[ ! -e "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/obj/zerocoin" ]]; then
            mkdir -p $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/obj/zerocoin
            print_info "Created src/obj/zerocoin directory"
        else
            print_info "src/obj/zerocoin directory already exists"
        fi

        cd $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/leveldb
        sudo chmod +x build_detect_platform

        print_status "Running make clean..."
        sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type d -exec chmod 755 {} \;
        sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type f -exec chmod 755 {} \;
        sudo make clean
        print_success "make clean completed"

        print_status "Precompiling leveldb dependencies..."
        sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type d -exec chmod 755 {} \;
        sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type f -exec chmod 755 {} \;
        sudo make libleveldb.a libmemenv.a
        print_success "Leveldb dependencies compiled"

        cd $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src
        sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type d -exec chmod 755 {} \;
        sudo find $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/ -type f -exec chmod 755 {} \;

        print_status "Patching makefile.unix with Berkeley DB and OpenSSL paths..."
        sed -i '/USE_UPNP:=0/i BDB_LIB_PATH = '${absolutepath}'/'${installtoserver}'/berkeley/db4/lib\nBDB_INCLUDE_PATH = '${absolutepath}'/'${installtoserver}'/berkeley/db4/include\nOPENSSL_LIB_PATH = '${absolutepath}'/'${installtoserver}'/openssl/lib\nOPENSSL_INCLUDE_PATH = '${absolutepath}'/'${installtoserver}'/openssl/include' makefile.unix
        sed -i '/USE_UPNP:=1/i BDB_LIB_PATH = '${absolutepath}'/'${installtoserver}'/berkeley/db4/lib\nBDB_INCLUDE_PATH = '${absolutepath}'/'${installtoserver}'/berkeley/db4/include\nOPENSSL_LIB_PATH = '${absolutepath}'/'${installtoserver}'/openssl/lib\nOPENSSL_INCLUDE_PATH = '${absolutepath}'/'${installtoserver}'/openssl/include' makefile.unix
        print_success "makefile.unix patched"

        print_status "Compiling with makefile.unix using ${NPROC} cores..."
        TMP=$(mktemp)
        make -j${NPROC} -f makefile.unix USE_UPNP=- 2>&1 | tee $TMP

        if [ ${PIPESTATUS[0]} -eq 0 ]; then
            print_success "Build completed successfully"
        else
            print_error "Build failed - check the error log"
            cat $TMP
            rm $TMP
            exit 1
        fi
        rm $TMP
    fi
fi

if [[ "$precompiled" == "true" ]]; then

    COINTARGZ=$(find . -type f -name "*.tar.gz")
    COINTGZ=$(find . -type f -name "*.tgz")
    COINZIP=$(find . -type f -name "*.zip")
    COIN7Z=$(find . -type f -name "*.7z")

    if [[ -f "$COINZIP" ]]; then
        hide_output sudo unzip -q "$COINZIP"
    elif [[ -f "$COINTARGZ" ]]; then
        hide_output sudo tar xzvf "$COINTARGZ"
    elif [[ -f "$COINTGZ" ]]; then
        hide_output sudo tar xzvf "$COINTGZ"
    elif [[ -f "$COIN7Z" ]]; then
        hide_output sudo 7z x "$COIN7Z"
    else
        print_error "No valid compressed files found (.zip, .tar.gz, .tgz, or .7z)."
        exit 1
    fi

    print_header "Searching for Wallet Files"

    # Find the directory containing wallet files
    WALLET_DIR=$(find . -type d -exec sh -c '
        cd "{}" 2>/dev/null &&
        if find . -maxdepth 1 -type f -executable \( -name "*coind" -o -name "*d" -o -name "*daemon" \) 2>/dev/null | grep -q .; then
            pwd
            exit 0
        fi' \; | head -n 1)

    if [[ -z "$WALLET_DIR" ]]; then
        print_error "Could not find directory containing wallet files."
        exit 1
    fi

    print_info "Found wallet directory: ${WALLET_DIR}"
    cd $WALLET_DIR

    COINDFIND=$(find ~+ -type f -executable \( -name "*coind" -o -name "*d" -o -name "*daemon" \) ! -name "*.sh" ! -name "README*" ! -name "*.md" ! -name "*.txt" 2>/dev/null | head -n 1)
    COINCLIFIND=$(find ~+ -type f -executable -name "*-cli" ! -name "*.sh" ! -name "README*" ! -name "*.md" ! -name "*.txt" 2>/dev/null | head -n 1)
    COINTXFIND=$(find ~+ -type f -executable -name "*-tx" ! -name "*.sh" ! -name "README*" ! -name "*.md" ! -name "*.txt" 2>/dev/null | head -n 1)
    COINUTILFIND=$(find ~+ -type f -executable -name "*-util" ! -name "*.sh" ! -name "README*" ! -name "*.md" ! -name "*.txt" 2>/dev/null | head -n 1)
    COINHASHFIND=$(find ~+ -type f -executable -name "*-hash" ! -name "*.sh" ! -name "README*" ! -name "*.md" ! -name "*.txt" 2>/dev/null | head -n 1)
    COINWALLETFIND=$(find ~+ -type f -executable -name "*-wallet" ! -name "*.sh" ! -name "README*" ! -name "*.md" ! -name "*.txt" 2>/dev/null | head -n 1)
    COINQTFIND=$(find . -type f -executable -name "*-qt" 2>/dev/null)

    declare -A wallet_files_found
    declare -A wallet_files_not_found

    if [[ -n "$COINDFIND" ]]; then
        wallet_files_found["Daemon"]=$(basename "$COINDFIND")
    else
        wallet_files_not_found["Daemon"]="true"
    fi

    [[ -n "$COINCLIFIND" ]] && wallet_files_found["CLI"]=$(basename "$COINCLIFIND") || wallet_files_not_found["CLI"]="true"
    [[ -n "$COINTXFIND" ]] && wallet_files_found["TX"]=$(basename "$COINTXFIND") || wallet_files_not_found["TX"]="true"
    [[ -n "$COINUTILFIND" ]] && wallet_files_found["Util"]=$(basename "$COINUTILFIND") || wallet_files_not_found["Util"]="true"
    [[ -n "$COINHASHFIND" ]] && wallet_files_found["Hash"]=$(basename "$COINHASHFIND") || wallet_files_not_found["Hash"]="true"
    [[ -n "$COINWALLETFIND" ]] && wallet_files_found["Wallet"]=$(basename "$COINWALLETFIND") || wallet_files_not_found["Wallet"]="true"
    [[ -n "$COINQTFIND" ]] && wallet_files_found["QT"]=$(basename "$COINQTFIND") || wallet_files_not_found["QT"]="true"

    echo -e "$GREEN === Found Wallet Files ===$NC"
    echo
    for type in "${!wallet_files_found[@]}"; do
        echo -e "$type: $YELLOW${wallet_files_found[$type]}$NC"
        sleep 0.5
    done

    echo
    echo -e "$RED => === Missing Wallet Files in zip/tar/7z file ===$NC"
    echo
    for type in "${!wallet_files_not_found[@]}"; do
        echo -e "$type: Not found"
        sleep 0.5
    done

    if [[ -n "$COINDFIND" ]]; then
        echo
        echo -e "$GREEN => Found Daemon: $YELLOW${wallet_files_found["Daemon"]}$NC"
    else
        echo
        print_error "Could not find daemon executable. Installation failed."
        exit 1
    fi

    echo -e "$CYAN === Install Directory ===$NC"
    echo -e "Executables will be installed to: $YELLOW/usr/bin$NC"

    echo
    coind=$(basename "$COINDFIND")
    [[ -n "$COINCLIFIND" ]] && coincli=$(basename "$COINCLIFIND")
    [[ -n "$COINTXFIND" ]] && cointx=$(basename "$COINTXFIND")
    [[ -n "$COINUTILFIND" ]] && coinutil=$(basename "$COINUTILFIND")
    [[ -n "$COINHASHFIND" ]] && coinhash=$(basename "$COINHASHFIND")
    [[ -n "$COINWALLETFIND" ]] && coinwallet=$(basename "$COINWALLETFIND")

fi

clear

if [[ "$precompiled" == "true" ]]; then

    cd $WALLET_DIR

    echo
    echo -e "$CYAN === List of files in $WALLET_DIR: $NC"
    echo
    for type in "${!wallet_files_found[@]}"; do
        echo -e "$type: $YELLOW${wallet_files_found[$type]}$NC"
    done
    echo
    echo -e "$CYAN --------------------------------------------------------------------------------------- 	$NC"
    echo

# SQSYIIMP_POOL_BINARY_NOTICE
printf '\n'
printf '%s\n' '---------------------------------------------------------------------------------------'
printf '%s\n' 'POOL NOTICE'
printf '%s\n' 'For normal mining pool operation, the essential binaries are:'
printf '%s\n' '  - Coin daemon / coind'
printf '%s\n' '  - Coin CLI'
printf '%s\n' ''
printf '%s\n' 'Example for Litecoin:'
printf '%s\n' '  Required : litecoind + litecoin-cli'
printf '%s\n' '  Optional : litecoin-tx, litecoin-wallet, litecoin-qt and coin-util'
printf '%s\n' ''
printf '%s\n' 'Optional binaries are not required for normal Stratum/RPC pool operation.'
printf '%s\n' '---------------------------------------------------------------------------------------'
printf '\n'

    read -r -e -p "please enter the coind name from the directory above, example $coind :" coind
    echo
    read -r -e -p "Is there a $coincli, example $coincli [y/N] :" ifcoincli
    if [[ ("$ifcoincli" == "y" || "$ifcoincli" == "Y") ]]; then
        read -r -e -p "Please enter the coin-cli name :" ifcoincli
    fi

    echo
    read -r -e -p "Is there a coin-tx [y/N] :" ifcointx
    if [[ ("$ifcointx" == "y" || "$ifcointx" == "Y") ]]; then
        read -r -e -p "Please enter the coin-tx name :" ifcointx
    fi

    echo
    read -r -e -p "Is there a coin-util [y/N] :" ifcoinutil
    if [[ ("$ifcoinutil" == "y" || "$ifcoinutil" == "Y") ]]; then
        read -r -e -p "Please enter the coin-util name :" ifcoinutil
    fi

    echo
    read -r -e -p "Is there a coin-wallet [y/N] :" ifcoinwallet
    if [[ ("$ifcoinwallet" == "y" || "$ifcoinwallet" == "Y") ]]; then
        read -r -e -p "Please enter the coin-wallet name :" ifcoinwallet
    fi

    echo
    read -r -e -p "Is there a coin-qt [y/N] :" ifcoinqt
    if [[ ("$ifcoinqt" == "y" || "$ifcoinqt" == "Y") ]]; then
        read -r -e -p "Please enter the coin-qt name :" ifcoinqt
    fi

    echo
    echo -e "$CYAN --------------------------------------------------------------------------------------- 	$NC"
    echo

    FILECOIN=/usr/bin/${coind}
    if [[ -f "$FILECOIN" ]]; then
        DAEMOND="true"
        SERVICE="${coind}"
        if [[ "${YIIMPCONF}" == "true" ]]; then
            DAEMON_DATADIR="$STORAGE_ROOT/wallets/.${coin,,}"
        else
            DAEMON_DATADIR="${absolutepath}/wallets/.${coin,,}"
        fi
        DAEMON_PIDS="$(mhp_find_daemon_pids "$coind" | tr '\n' ' ')"
        if [[ -n "${DAEMON_PIDS// }" ]]; then
            if [[ ("${YIIMPCONF}" == "true") ]]; then
                if [[ ("$ifcoincli" == "y" || "$ifcoincli" == "Y") ]]; then
                    sudo -u "${STORAGE_USER:-crypto-data}" "/usr/bin/${coincli}" -datadir=$STORAGE_ROOT/wallets/."${coin,,}" -conf="${coin,,}".conf stop
                else
                    sudo -u "${STORAGE_USER:-crypto-data}" "/usr/bin/${coind}" -datadir=$STORAGE_ROOT/wallets/."${coin,,}" -conf="${coin,,}".conf stop
                fi
            else
                if [[ ("$ifcoincli" == "y" || "$ifcoincli" == "Y") ]]; then
                    sudo -u "${STORAGE_USER:-crypto-data}" "/usr/bin/${coincli}" -datadir=${absolutepath}/wallets/."${coin,,}" -conf="${coin,,}".conf stop
                else
                    sudo -u "${STORAGE_USER:-crypto-data}" "/usr/bin/${coind}" -datadir=${absolutepath}/wallets/."${coin,,}" -conf="${coin,,}".conf stop
                fi
            fi
            print_status "Stopping daemon ${coind}..."
            if ! mhp_wait_for_daemon_shutdown \
                "$DAEMON_PIDS" \
                "$coind" \
                "$DAEMON_DATADIR" \
                1800
            then
                print_error "Refusing to replace $coind while the old daemon is still active"
                return 1 2>/dev/null || exit 1
            fi
            echo
            print_success "Daemon stopped"
        fi
    fi
fi

clear

# Strip and copy to /usr/bin
if [[ ("$precompiled" == "true") ]]; then
    cd $WALLET_DIR

    COINDFIND=$(find ~+ -type f -executable \( -name "*coind" -o -name "*d" -o -name "*daemon" \) ! -name "*.sh" ! -name "README*" ! -name "*.md" ! -name "*.txt" 2>/dev/null | head -n 1)
    COINCLIFIND=$(find ~+ -type f -executable -name "*-cli" ! -name "*.sh" ! -name "README*" ! -name "*.md" ! -name "*.txt" 2>/dev/null | head -n 1)
    COINTXFIND=$(find ~+ -type f -executable -name "*-tx" ! -name "*.sh" ! -name "README*" ! -name "*.md" ! -name "*.txt" 2>/dev/null | head -n 1)
    COINUTILFIND=$(find ~+ -type f -executable -name "*-util" ! -name "*.sh" ! -name "README*" ! -name "*.md" ! -name "*.txt" 2>/dev/null | head -n 1)
    COINHASHFIND=$(find ~+ -type f -executable -name "*-hash" ! -name "*.sh" ! -name "README*" ! -name "*.md" ! -name "*.txt" 2>/dev/null | head -n 1)
    COINWALLETFIND=$(find ~+ -type f -executable -name "*-wallet" ! -name "*.sh" ! -name "README*" ! -name "*.md" ! -name "*.txt" 2>/dev/null | head -n 1)

    if [[ -f "$COINDFIND" ]]; then
        coind=$(basename $COINDFIND)

        if [[ -f "$COINCLIFIND" ]]; then
            coincli=$(basename $COINCLIFIND)
        fi

        FILECOIN=/usr/bin/${coind}
        if [[ -f "$FILECOIN" ]]; then
            DAEMOND="true"
            SERVICE="${coind}"
            if [[ "${YIIMPCONF}" == "true" ]]; then
                DAEMON_DATADIR="$STORAGE_ROOT/wallets/.${coin,,}"
            else
                DAEMON_DATADIR="${absolutepath}/wallets/.${coin,,}"
            fi
            DAEMON_PIDS="$(mhp_find_daemon_pids "$coind" | tr '\n' ' ')"
            if [[ -n "${DAEMON_PIDS// }" ]]; then
                if [[ ("${YIIMPCONF}" == "true") ]]; then
                    if [[ -f "$COINCLIFIND" ]]; then
                        sudo -u "${STORAGE_USER:-crypto-data}" "/usr/bin/${coincli}" -datadir=$STORAGE_ROOT/wallets/."${coin,,}" -conf="${coin,,}".conf stop
                    else
                        sudo -u "${STORAGE_USER:-crypto-data}" "/usr/bin/${coind}" -datadir=$STORAGE_ROOT/wallets/."${coin,,}" -conf="${coin,,}".conf stop
                    fi
                else
                    if [[ -f "${COINCLIFIND}" ]]; then
                        sudo -u "${STORAGE_USER:-crypto-data}" "/usr/bin/${coincli}" -datadir=${absolutepath}/wallets/."${coin,,}" -conf="${coin,,}".conf stop
                    else
                        sudo -u "${STORAGE_USER:-crypto-data}" "/usr/bin/${coind}" -datadir=${absolutepath}/wallets/."${coin,,}" -conf="${coin,,}".conf stop
                    fi
                fi
                print_status "Stopping daemon ${coind}..."
                if ! mhp_wait_for_daemon_shutdown \
                    "$DAEMON_PIDS" \
                    "$coind" \
                    "$DAEMON_DATADIR" \
                    1800
                then
                    print_error "Refusing to replace $coind while the old daemon is still active"
                    return 1 2>/dev/null || exit 1
                fi
                echo
                print_success "Daemon stopped"
            fi
        fi

        sudo strip $COINDFIND
        sudo cp $COINDFIND /usr/bin
        sudo chmod +x /usr/bin/${coind}
        coindmv=true
        print_success "Installed ${coind} to /usr/bin/${coind}"
    fi

    if [[ -f "$COINCLIFIND" ]]; then
        sudo strip $COINCLIFIND
        sudo cp $COINCLIFIND /usr/bin
        sudo chmod +x /usr/bin/${coincli}
        coinclimv=true
        print_success "Installed ${coincli} to /usr/bin/${coincli}"
    fi

    if [[ -f "$COINTXFIND" ]]; then
        cointx=$(basename $COINTXFIND)
        sudo strip $COINTXFIND
        sudo cp $COINTXFIND /usr/bin
        sudo chmod +x /usr/bin/${cointx}
        cointxmv=true
        print_success "Installed ${cointx} to /usr/bin/${cointx}"
    fi

    if [[ -f "$COINUTILFIND" ]]; then
        coinutil=$(basename $COINUTILFIND)
        sudo strip $COINUTILFIND
        sudo cp $COINUTILFIND /usr/bin
        sudo chmod +x /usr/bin/${coinutil}
        coinutilmv=true
        print_success "Installed ${coinutil} to /usr/bin/${coinutil}"
    fi

    if [[ -f "$COINHASHFIND" ]]; then
        coinhash=$(basename $COINHASHFIND)
        sudo strip $COINHASHFIND
        sudo cp $COINHASHFIND /usr/bin
        sudo chmod +x /usr/bin/${coinhash}
        coinhashmv=true
        print_success "Installed ${coinhash} to /usr/bin/${coinhash}"
    fi

    if [[ -f "$COINWALLETFIND" ]]; then
        coinwallet=$(basename $COINWALLETFIND)
        sudo strip $COINWALLETFIND
        sudo cp $COINWALLETFIND /usr/bin
        sudo chmod +x /usr/bin/${coinwallet}
        coinwalletmv=true
        print_success "Installed ${coinwallet} to /usr/bin/${coinwallet}"
    fi

    print_divider
else
    print_divider

    cd $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src
    print_header "Detecting executables in $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src"

    COINDFIND=$(find ~+ -type f -executable \( -name "*coind" -o -name "*d" -o -name "*daemon" \) ! -name "*.sh" ! -name "README*" ! -name "*.md" ! -name "*.txt" 2>/dev/null | head -n 1)
    sleep 0.5
    COINCLIFIND=$(find ~+ -type f -executable -name "*-cli" ! -name "*.sh" ! -name "README*" ! -name "*.md" ! -name "*.txt" 2>/dev/null | head -n 1)
    sleep 0.5
    COINTXFIND=$(find ~+ -type f -executable -name "*-tx" ! -name "*.sh" ! -name "README*" ! -name "*.md" ! -name "*.txt" 2>/dev/null | head -n 1)
    sleep 0.5
    COINUTILFIND=$(find ~+ -type f -executable -name "*-util" ! -name "*.sh" ! -name "README*" ! -name "*.md" ! -name "*.txt" 2>/dev/null | head -n 1)
    sleep 0.5
    COINHASHFIND=$(find ~+ -type f -executable -name "*-hash" ! -name "*.sh" ! -name "README*" ! -name "*.md" ! -name "*.txt" 2>/dev/null | head -n 1)
    sleep 0.5
    COINWALLETFIND=$(find ~+ -type f -executable -name "*-wallet" ! -name "*.sh" ! -name "README*" ! -name "*.md" ! -name "*.txt" 2>/dev/null | head -n 1)
    sleep 0.5
    COINQTFIND=$(find . -type f -executable -name "*-qt" 2>/dev/null)

    declare -A wallet_files_found
    declare -A wallet_files_not_found

    if [[ -n "$COINDFIND" ]]; then
        wallet_files_found["Daemon"]=$(basename "$COINDFIND")
        coind=$(basename "$COINDFIND")
    else
        wallet_files_not_found["Daemon"]="true"
    fi

    if [[ -n "$COINCLIFIND" ]]; then
        wallet_files_found["CLI"]=$(basename "$COINCLIFIND")
        coincli=$(basename "$COINCLIFIND")
    else
        wallet_files_not_found["CLI"]="true"
    fi

    if [[ -n "$COINTXFIND" ]]; then
        wallet_files_found["TX"]=$(basename "$COINTXFIND")
        cointx=$(basename "$COINTXFIND")
    else
        wallet_files_not_found["TX"]="true"
    fi

    if [[ -n "$COINUTILFIND" ]]; then
        wallet_files_found["Util"]=$(basename "$COINUTILFIND")
        coinutil=$(basename "$COINUTILFIND")
    else
        wallet_files_not_found["Util"]="true"
    fi

    if [[ -n "$COINHASHFIND" ]]; then
        wallet_files_found["Hash"]=$(basename "$COINHASHFIND")
        coinhash=$(basename "$COINHASHFIND")
    else
        wallet_files_not_found["Hash"]="true"
    fi

    if [[ -n "$COINWALLETFIND" ]]; then
        wallet_files_found["Wallet"]=$(basename "$COINWALLETFIND")
        coinwallet=$(basename "$COINWALLETFIND")
    else
        wallet_files_not_found["Wallet"]="true"
    fi

    if [[ -n "$COINQTFIND" ]]; then
        wallet_files_found["QT"]=$(basename "$COINQTFIND")
        coinqt=$(basename "$COINQTFIND")
    else
        wallet_files_not_found["QT"]="true"
    fi

    echo -e "$GREEN === Found Wallet Files ===$NC"
    echo
    for type in "${!wallet_files_found[@]}"; do
        echo -e "$type: $YELLOW${wallet_files_found[$type]}$NC"
        sleep 0.5
    done

    echo
    echo -e "$RED === Missing Wallet Files ===$NC"
    echo
    for type in "${!wallet_files_not_found[@]}"; do
        echo -e "$type: Not found"
        sleep 0.5
    done

    if [[ -n "$COINDFIND" ]]; then
        echo
        echo -e "$GREEN => Found Daemon: $YELLOW${wallet_files_found["Daemon"]}$NC"
    else
        echo
        print_error "Could not find daemon executable. Update failed."
        exit 1
    fi

    echo -e "$CYAN === Install Directory ===$NC"
    echo -e "Executables will be installed to: $YELLOW/usr/bin$NC"
    echo

    # Stop existing daemon before update
    FILECOIN=/usr/bin/${coind}
    if [[ -f "$FILECOIN" ]]; then
        DAEMOND="true"
        SERVICE="${coind}"
        if [[ "${YIIMPCONF}" == "true" ]]; then
            DAEMON_DATADIR="$STORAGE_ROOT/wallets/.${coin,,}"
        else
            DAEMON_DATADIR="${absolutepath}/wallets/.${coin,,}"
        fi
        DAEMON_PIDS="$(mhp_find_daemon_pids "$coind" | tr '\n' ' ')"
        if [[ -n "${DAEMON_PIDS// }" ]]; then
            if [[ ("${YIIMPCONF}" == "true") ]]; then
                if [[ -n "$COINCLIFIND" ]]; then
                    sudo -u "${STORAGE_USER:-crypto-data}" "/usr/bin/${coincli}" -datadir=$STORAGE_ROOT/wallets/."${coin,,}" -conf="${coin,,}".conf stop
                else
                    sudo -u "${STORAGE_USER:-crypto-data}" "/usr/bin/${coind}" -datadir=$STORAGE_ROOT/wallets/."${coin,,}" -conf="${coin,,}".conf stop
                fi
            else
                if [[ -n "$COINCLIFIND" ]]; then
                    sudo -u "${STORAGE_USER:-crypto-data}" "/usr/bin/${coincli}" -datadir=${absolutepath}/wallets/."${coin,,}" -conf="${coin,,}".conf stop
                else
                    sudo -u "${STORAGE_USER:-crypto-data}" "/usr/bin/${coind}" -datadir=${absolutepath}/wallets/."${coin,,}" -conf="${coin,,}".conf stop
                fi
            fi
            print_status "Stopping daemon ${coind}..."
            if ! mhp_wait_for_daemon_shutdown \
                "$DAEMON_PIDS" \
                "$coind" \
                "$DAEMON_DATADIR" \
                1800
            then
                print_error "Refusing to replace $coind while the old daemon is still active"
                return 1 2>/dev/null || exit 1
            fi
            echo
            print_success "Daemon stopped"
        fi
    fi

    print_header "Installing Binaries"

    if [[ -n "$COINDFIND" ]]; then
        print_status "Installing daemon to /usr/bin/${coind}..."
        mhp_install_coin_binary "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/${coind}" "${coind}" "daemon" || { return 1 2>/dev/null || exit 1; }
        coind="$MHP_INSTALLED_BINARY"
        sudo strip /usr/bin/${coind}
        coindmv=true
        print_success "Daemon installed"
    fi

    if [[ -n "$COINCLIFIND" ]]; then
        print_status "Installing CLI to /usr/bin/${coincli}..."
        mhp_install_coin_binary "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/${coincli}" "${coincli}" "cli" || { return 1 2>/dev/null || exit 1; }
        coincli="$MHP_INSTALLED_BINARY"
        sudo strip /usr/bin/${coincli}
        coinclimv=true
        print_success "CLI installed"
    fi

    if [[ -n "$COINTXFIND" ]]; then
        print_status "Installing TX to /usr/bin/${cointx}..."
        mhp_install_coin_binary "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/${cointx}" "${cointx}" "tx" || { return 1 2>/dev/null || exit 1; }
        cointx="$MHP_INSTALLED_BINARY"
        sudo strip /usr/bin/${cointx}
        cointxmv=true
        print_success "TX installed"
    fi

    if [[ -n "$COINUTILFIND" ]]; then
        print_status "Installing UTIL to /usr/bin/${coinutil}..."
        mhp_install_coin_binary "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/${coinutil}" "${coinutil}" "util" || { return 1 2>/dev/null || exit 1; }
        coinutil="$MHP_INSTALLED_BINARY"
        sudo strip /usr/bin/${coinutil}
        coinutilmv=true
        print_success "UTIL installed"
    fi

    if [[ -n "$COINHASHFIND" ]]; then
        print_status "Installing HASH to /usr/bin/${coinhash}..."
        mhp_install_coin_binary "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/${coinhash}" "${coinhash}" "hash" || { return 1 2>/dev/null || exit 1; }
        coinhash="$MHP_INSTALLED_BINARY"
        sudo strip /usr/bin/${coinhash}
        coinhashmv=true
        print_success "HASH installed"
    fi

    if [[ -n "$COINWALLETFIND" ]]; then
        print_status "Installing WALLET to /usr/bin/${coinwallet}..."
        mhp_install_coin_binary "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/${coinwallet}" "${coinwallet}" "wallet" || { return 1 2>/dev/null || exit 1; }
        coinwallet="$MHP_INSTALLED_BINARY"
        sudo strip /usr/bin/${coinwallet}
        coinwalletmv=true
        print_success "WALLET installed"
    fi

    if [[ -n "$COINQTFIND" ]]; then
        print_status "Installing QT to /usr/bin/${coinqt}..."
        mhp_install_coin_binary "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/${coinqt}" "${coinqt}" "qt" || { return 1 2>/dev/null || exit 1; }
        coinqt="$MHP_INSTALLED_BINARY"
        sudo strip /usr/bin/${coinqt}
        coinqtmv=true
        print_success "QT installed"
    fi

    print_divider
fi

print_header "Configuration Verification"
print_info "Please verify the config file is correct."
read -n 1 -s -r -p "Press any key to continue"
echo

if [[ "$YIIMPCONF" == "true" ]]; then
    sudo nano $STORAGE_ROOT/wallets/."${coin,,}"/${coin,,}.conf
else
    sudo nano ${absolutepath}/wallets/."${coin,,}"/${coin,,}.conf
fi

clear
cd $STORAGE_ROOT/daemon_builder

# Cleanup build artifacts
if [[ -f "$STORAGE_ROOT/daemon_builder/temp_coin_builds/.lastcoin.conf" ]]; then
    sudo rm -f $STORAGE_ROOT/daemon_builder/temp_coin_builds/.lastcoin.conf
fi

if [[ -d "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}" ]]; then
    sudo rm -rf $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}
fi

if [[ -f "$STORAGE_ROOT/daemon_builder/.daemon_builder.my.cnf" ]]; then
    sudo rm -f $STORAGE_ROOT/daemon_builder/.daemon_builder.my.cnf
fi

if [[ -f "$ADDPORTCONF" ]]; then
    sudo rm -f $STORAGE_ROOT/daemon_builder/.addport.cnf
fi

clear
echo
figlet -f slant -w 100 "    DaemonBuilder" | lolcat
echo

print_header "Update Summary"

print_success "UPDATE of ${coind::-1} completed"

print_divider

print_header "Installed Components"

if [[ "$coindmv" == "true" ]]; then
    print_info "Daemon       : ${MAGENTA}${coind}${NC}"
    print_info "Location     : ${YELLOW}/usr/bin/${coind}${NC}"
fi

if [[ "$coinclimv" == "true" ]]; then
    print_info "CLI Tool     : ${MAGENTA}${coincli}${NC}"
    print_info "Location     : ${YELLOW}/usr/bin/${coincli}${NC}"
fi

if [[ "$cointxmv" == "true" ]]; then
    print_info "TX Tool      : ${MAGENTA}${cointx}${NC}"
    print_info "Location     : ${YELLOW}/usr/bin/${cointx}${NC}"
fi

if [[ "$coinutilmv" == "true" ]]; then
    print_info "Utility Tool : ${MAGENTA}${coinutil}${NC}"
    print_info "Location     : ${YELLOW}/usr/bin/${coinutil}${NC}"
fi

if [[ "$coinhashmv" == "true" ]]; then
    print_info "Hash Tool    : ${MAGENTA}${coinhash}${NC}"
    print_info "Location     : ${YELLOW}/usr/bin/${coinhash}${NC}"
fi

if [[ "$coinwalletmv" == "true" ]]; then
    print_info "Wallet Tool  : ${MAGENTA}${coinwallet}${NC}"
    print_info "Location     : ${YELLOW}/usr/bin/${coinwallet}${NC}"
fi

print_divider

# Start the daemon
print_header "Starting Daemon"
print_status "Initializing ${coin^^} daemon..."

if [[ "$YIIMPCONF" == "true" ]]; then
    sudo -u "${STORAGE_USER:-crypto-data}" "/usr/bin/${coind}" -datadir=$STORAGE_ROOT/wallets/."${coin,,}" -conf="${coin,,}".conf -daemon -shrinkdebugfile
    print_success "${coin^^} daemon started successfully"
else
    sudo -u "${STORAGE_USER:-crypto-data}" "/usr/bin/${coind}" -datadir=${absolutepath}/wallets/."${coin,,}" -conf="${coin,,}".conf -daemon -shrinkdebugfile
    print_success "${coin^^} daemon started successfully"
fi

print_divider

echo -e "$CYAN =========================================================================== $NC"
echo -e "$GREEN Update process completed successfully! $NC"
echo -e "$RED Type ${MAGENTA}daemonbuilder${NC}${RED} at any time to install another coin! $NC"
echo -e "$CYAN =========================================================================== $NC"
echo

exit
