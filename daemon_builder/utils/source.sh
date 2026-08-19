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


# This is the source file that compiles coin daemon.
#
# Author: SabiasQue.Space
#
# It uses:
#  Berkeley 4.8 with autogen.sh file.
#  Berkeley 5.1 with autogen.sh file.
#  Berkeley 5.3 with autogen.sh file.
#  Berkeley 6.2 with autogen.sh file.
#  makefile.unix file.
#  CMake file.
#  UTIL folder contains BUILD.sh file.
#  precompiled coin. NEED TO BE LINUX Version!
#
# Updated: 2026-03-28

source /etc/daemonbuilder.sh
source /etc/functions.sh
source $STORAGE_ROOT/daemon_builder/.daemon_builder.my.cnf
source $STORAGE_ROOT/daemon_builder/conf/info.sh

YIIMPOLL=/etc/yiimpool.conf
if [[ -f "$YIIMPOLL" ]]; then
    source /etc/yiimpool.conf
    YIIMPCONF=true
fi

CREATECOIN=true
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

convertlistalgos=$(find ${PATH_STRATUM}/config/ -mindepth 1 -maxdepth 1 -type f -not -name '.*' -not -name '*.sh' -not -name '*.log' -not -name 'stratum.*' -not -name '*.*.*' -iname '*.conf' -execdir basename -s '.conf' {} +);
optionslistalgos=$(echo -e "${convertlistalgos}" | awk '{ printf "%s on\n", $1}' | sort | uniq | grep [[:alnum:]])

DIALOGFORLISTALGOS=${DIALOGFORLISTALGOS=dialog}
tempfile=$(mktemp)
trap "rm -f $tempfile" 0 1 2 5 15

$DIALOGFORLISTALGOS --colors --title "\Zb\Zr\Z7| Select Algorithm: ${coin^^} |" --clear --colors --no-items --nocancel --shadow \
--radiolist "\n\
    Select the mining algorithm for your coin.\n\
    Use UP/DOWN arrows or number keys 1-9 to navigate.\n\
    Press SPACE to select an option.\n\n\
Choose from available algorithms:" \
55 60 47 $optionslistalgos 2> $tempfile

retvalalgoselected=$?
ALGOSELECTED=$(cat $tempfile)
case $retvalalgoselected in
    0)
        coinalgo="${ALGOSELECTED}"
        print_success "Selected algorithm: ${ALGOSELECTED}"
        ;;
    1)
        print_error "Installation cancelled by user"
        print_info "Use daemonbuilder to start a new installation"
        exit
        ;;
    255)
        print_error "Installation cancelled (ESC pressed)"
        print_info "Use daemonbuilder to start a new installation"
        exit
        ;;
esac

print_divider

print_header "Coin Binary Installation"

if [[ ("$precompiled" == "true") ]]; then
    print_status "Preparing to install precompiled binary..."

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
print_header "Starting Installation: ${coin^^}"

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
        echo -e "$RED => No valid compressed files found (.zip, .tar.gz, .tgz, or .7z).$NC"
        exit 1
    fi

    echo
    echo -e "$CYAN === Searching for wallet files ===$NC"
    echo

    # Find the directory containing wallet files
    WALLET_DIR=$(find . -type d -exec sh -c '
        cd "{}" 2>/dev/null &&
        if find . -maxdepth 1 -type f -executable \( -name "*coind" -o -name "*d" -o -name "*daemon" \) 2>/dev/null | grep -q .; then
            pwd
            exit 0
        fi' \; | head -n 1)

    if [[ -z "$WALLET_DIR" ]]; then
        echo -e "$RED => Could not find directory containing wallet files.$NC"
        exit 1
    fi

    echo -e "$CYAN === Found wallet directory: $YELLOW$WALLET_DIR $NC"
    cd $WALLET_DIR

    # Now search for executables in the correct directory
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
        echo -e "$RED=> Could not find daemon executable. Installation failed.$NC"
        echo
        exit 1
    fi

    echo -e "$CYAN === Install Directory ===$NC"
    echo -e "Executables will be installed to: $YELLOW$HOME/daemon_builder/src$NC"

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

    echo
    echo -e "${CYAN}===============================================================================${NC}"
    echo -e "${GREEN}                     BINARIES REQUIRED FOR THE POOL${NC}"
    echo -e "${CYAN}===============================================================================${NC}"
    echo
    echo -e "  ${GREEN}[REQUIRED]${NC}     Daemon : ${YELLOW}${coind}${NC}"
    echo -e "                 Runs the blockchain node used by YiiMP."
    echo
    echo -e "  ${GREEN}[RECOMMENDED]${NC}  CLI    : ${YELLOW}${coincli}${NC}"
    echo -e "                 Used to query blocks, peers, wallet and RPC status."
    echo
    echo -e "  ${YELLOW}[OPTIONAL]${NC}     TX     : ${cointx:-not detected}"
    echo -e "                 Offline transaction utility."
    echo
    echo -e "  ${YELLOW}[OPTIONAL]${NC}     Wallet : ${coinwallet:-not detected}"
    echo -e "                 Additional wallet management utility."
    echo
    echo -e "  ${RED}[NOT NEEDED]${NC}   QT     : ${coinqt:-not detected}"
    echo -e "                 Graphical wallet. Not required on a pool server."
    echo
    echo -e "${CYAN}-------------------------------------------------------------------------------${NC}"
    echo
    echo -e "${GREEN}For MegaHashPool you normally need:${NC}"
    echo -e "    ${GREEN}✓${NC} ${coind}"
    echo -e "    ${GREEN}✓${NC} ${coincli}"
    echo
    echo -e "Enter the ${YELLOW}exact daemon filename${NC} shown in the list above."
    echo

    read -r -e -p "Daemon [${coind}]: " daemon_input

    # Keep detected daemon as default when ENTER is pressed.
    if [[ -n "${daemon_input}" ]]; then
        coind="${daemon_input}"
    fi
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
        if pgrep -x "$SERVICE" >/dev/null; then
            if [[ ("${YIIMPCONF}" == "true") ]]; then
                if [[ ("$ifcoincli" == "y" || "$ifcoincli" == "Y") ]]; then
                    sudo -u crypto-data "/usr/bin/${coincli}" -datadir=$STORAGE_ROOT/wallets/."${coin,,}" -conf="${coin,,}".conf stop
                else
                    sudo -u crypto-data "/usr/bin/${coind}" -datadir=$STORAGE_ROOT/wallets/."${coin,,}" -conf="${coin,,}".conf stop
                fi
            else
                if [[ ("$ifcoincli" == "y" || "$ifcoincli" == "Y") ]]; then
                    sudo -u crypto-data "/usr/bin/${coincli}" -datadir=${absolutepath}/wallets/."${coin,,}" -conf="${coin,,}".conf stop
                else
                    sudo -u crypto-data "/usr/bin/${coind}" -datadir=${absolutepath}/wallets/."${coin,,}" -conf="${coin,,}".conf stop
                fi
            fi
            echo -e "$CYAN --------------------------------------------------------------------------- $NC"
            secstosleep=$((1 * 20))
            while [ $secstosleep -gt 0 ]; do
                echo -ne "$GREEN	STOP THE DAEMON => $YELLOW${coind}$GREEN Sleep $CYAN$secstosleep$GREEN ...$NC\033[0K\r"

                : $((secstosleep--))
            done
            echo -e "$CYAN --------------------------------------------------------------------------- $NC $GREEN"
            echo -e "$GREEN Done... $NC"
            echo -e "$NC$CYAN --------------------------------------------------------------------------- $NC"
            echo
        fi
    fi
fi

clear

# Strip and copy to /usr/bin
if [[ ("$precompiled" == "true") ]]; then
    cd $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/${repzipcoin}/

    # The daemon name was already detected above.
    # Do NOT use "*d": it also matches files such as README.md.
    COINDFIND=$(find ~+ -type f -name "${coind}" -print -quit)
    sleep 0.5
    COINCLIFIND=$(find ~+ -type f -name "*-cli" -print -quit)
    sleep 0.5
    COINTXFIND=$(find ~+ -type f -name "*-tx")
    sleep 0.5
    COINUTILFIND=$(find ~+ -type f -name "*-util")
    sleep 0.5
    COINHASHFIND=$(find ~+ -type f -name "*-hash")
    sleep 0.5
    COINWALLETFIND=$(find ~+ -type f -name "*-wallet")


    if [[ -f "$COINDFIND" ]]; then
        coind=$(basename $COINDFIND)

        if [[ -f "$COINCLIFIND" ]]; then
            coincli=$(basename $COINCLIFIND)
        fi

        FILECOIN=/usr/bin/${coind}
        if [[ -f "$FILECOIN" ]]; then
            DAEMOND="true"
            SERVICE="${coind}"
            if pgrep -x "$SERVICE" >/dev/null; then
                if [[ ("${YIIMPCONF}" == "true") ]]; then
                    if [[ -f "$COINCLIFIND" ]]; then
                        sudo -u crypto-data "/usr/bin/${coincli}" -datadir=$STORAGE_ROOT/wallets/."${coin,,}" -conf="${coin,,}".conf stop
                    else
                        sudo -u crypto-data "/usr/bin/${coind}" -datadir=$STORAGE_ROOT/wallets/."${coin,,}" -conf="${coin,,}".conf stop
                    fi
                else
                    if [[ -f "${COINCLIFIND}" ]]; then
                        sudo -u crypto-data "/usr/bin/${coincli}" -datadir=${absolutepath}/wallets/."${coin,,}" -conf="${coin,,}".conf stop
                    else
                        sudo -u crypto-data "/usr/bin/${coind}" -datadir=${absolutepath}/wallets/."${coin,,}" -conf="${coin,,}".conf stop
                    fi
                fi
                echo -e "$CYAN --------------------------------------------------------------------------- $NC"
                secstosleep=$((1 * 20))
                while [ $secstosleep -gt 0 ]; do
                    echo -ne "$GREEN	STOP THE DAEMON => $YELLOW${coind}$GREEN Sleep $CYAN$secstosleep$GREEN ...$NC"

                    : $((secstosleep--))
                done
                echo -e "$CYAN --------------------------------------------------------------------------- $NC $GREEN"
                echo -e "$GREEN Done... $NC"
                echo -e "$NC$CYAN --------------------------------------------------------------------------- $NC"
                echo
            fi
        fi

        # ------------------------------------------------------------
        # REQUIRED DAEMON INSTALLATION
        # ------------------------------------------------------------

        DAEMON_PACKAGE_NAME="$(basename "$COINDFIND")"

        print_status "Installing required daemon: ${DAEMON_PACKAGE_NAME}"

        if ! mhp_install_coin_binary \
            "$COINDFIND" \
            "$DAEMON_PACKAGE_NAME" \
            "daemon"
        then
            print_error "Failed to install the required daemon binary"
            print_error "Source: ${COINDFIND}"
            exit 1
        fi

        # mhp_install_coin_binary returns the final canonical filename.
        coind="$MHP_INSTALLED_BINARY"

        # Strip when supported. Some binaries cannot/should not be stripped.
        sudo strip "/usr/bin/${coind}" 2>/dev/null || true

        if [[ ! -x "/usr/bin/${coind}" ]]; then
            print_error "Daemon verification failed after installation"
            print_error "Expected executable: /usr/bin/${coind}"
            exit 1
        fi

        coindmv=true

        print_success "Required daemon installed and verified"
        print_info "Daemon         : ${coind}"
        print_info "Location       : /usr/bin/${coind}"

        echo
        echo -e "$CYAN ----------------------------------------------------------------------------------- $NC"
        echo
        echo -e "$GREEN  ${coind} moving to =>$YELLOW /usr/bin/$NC${coind} $NC"

        clear

    fi

    if [[ -f "$COINCLIFIND" ]]; then
        sudo strip $COINCLIFIND

        sudo cp $COINCLIFIND /usr/bin
        sudo chmod +x /usr/bin/${coincli}
        coinclimv=true

        echo -e "$GREEN  Coin-cli moving to => /usr/bin/$NC$YELLOW${coincli} $NC"

    fi

    if [[ -f "$COINTXFIND" ]]; then
        cointx=$(basename $COINTXFIND)
        sudo strip $COINTXFIND

        sudo cp $COINTXFIND /usr/bin
        sudo chmod +x /usr/bin/${cointx}
        cointxmv=true

        echo -e "$GREEN  Coin-tx moving to => /usr/bin/$NC$YELLOW${cointx} $NC"

    fi

    if [[ -f "$COINUTILFIND" ]]; then
        coinutil=$(basename $COINUTILFIND)
        sudo strip $COINUTILFIND

        sudo cp $COINUTILFIND /usr/bin
        sudo chmod +x /usr/bin/${coinutil}
        coinutilmv=true

        echo -e "$GREEN  Coin-util moving to => /usr/bin/$NC$YELLOW${coinutil} $NC"

    fi

    if [[ -f "$COINHASHFIND" ]]; then
        coinhash=$(basename $COINHASHFIND)
        sudo strip $COINHASHFIND

        sudo cp $COINHASHFIND /usr/bin
        sudo chmod +x /usr/bin/${coinhash}
        coinhashmv=true

        echo -e "$GREEN  Coin-hash moving to => /usr/bin/$NC$YELLOW${coinhash} $NC"

    fi

    if [[ -f "$COINWALLETFIND" ]]; then
        coinwallet=$(basename $COINWALLETFIND)
        sudo strip $COINWALLETFIND

        sudo cp $COINWALLETFIND /usr/bin
        sudo chmod +x /usr/bin/${coinwallet}
        coinwalletmv=true

        print_success "Installed ${coinwallet} binary to /usr/bin/${coinwallet}"
    else
        print_error "Precompiled binary not found"
    fi
    echo
    echo -e "$CYAN --------------------------------------------------------------------------------------- $NC"
    echo
else
    echo
    echo -e "$CYAN --------------------------------------------------------------------------------------- $NC"
    echo
    cd $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src
    print_header "Detecting executables in $STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src"
    print_divider

    # Now search for executables in the correct directory
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
        echo -e "$RED=> Could not find daemon executable. Installation failed.$NC"
        echo
        exit 1
    fi

    echo -e "$CYAN === Install Directory ===$NC"
    echo -e "Executables will be installed to: $YELLOW/usr/bin$NC"
    echo

    echo -e "$GREEN  Daemon moving to => /usr/bin/$NC$YELLOW${coind} $NC"

    mhp_install_coin_binary "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/${coind}" "${coind}" "daemon" || { return 1 2>/dev/null || exit 1; }
    coind="$MHP_INSTALLED_BINARY"
    sudo strip /usr/bin/${coind}
    coindmv=true

    if [[ -n "$COINCLIFIND" ]]; then
        echo -e "$GREEN  CLI moving to => /usr/bin/$NC$YELLOW${coincli} $NC"
        mhp_install_coin_binary "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/${coincli}" "${coincli}" "cli" || { return 1 2>/dev/null || exit 1; }
        coincli="$MHP_INSTALLED_BINARY"
        sudo strip /usr/bin/${coincli}
        coinclimv=true
    fi

    if [[ -n "$COINTXFIND" ]]; then
        echo -e "$GREEN  TX moving to => /usr/bin/$NC$YELLOW${cointx} $NC"
        mhp_install_coin_binary "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/${cointx}" "${cointx}" "tx" || { return 1 2>/dev/null || exit 1; }
        cointx="$MHP_INSTALLED_BINARY"
        sudo strip /usr/bin/${cointx}
        cointxmv=true
    fi

    if [[ -n "$COINUTILFIND" ]]; then
        echo -e "$GREEN  UTIL moving to => /usr/bin/$NC$YELLOW${coinutil} $NC"
        mhp_install_coin_binary "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/${coinutil}" "${coinutil}" "util" || { return 1 2>/dev/null || exit 1; }
        coinutil="$MHP_INSTALLED_BINARY"
        sudo strip /usr/bin/${coinutil}
        coinutilmv=true
    fi

    if [[ -n "$COINHASHFIND" ]]; then
        echo -e "$GREEN  HASH moving to => /usr/bin/$NC$YELLOW${coinhash} $NC"
        mhp_install_coin_binary "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/${coinhash}" "${coinhash}" "hash" || { return 1 2>/dev/null || exit 1; }
        coinhash="$MHP_INSTALLED_BINARY"
        sudo strip /usr/bin/${coinhash}
        coinhashmv=true
    fi

    if [[ -n "$COINWALLETFIND" ]]; then
        echo -e "$GREEN  WALLET moving to => /usr/bin/$NC$YELLOW${coinwallet} $NC"
        mhp_install_coin_binary "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/${coinwallet}" "${coinwallet}" "wallet" || { return 1 2>/dev/null || exit 1; }
        coinwallet="$MHP_INSTALLED_BINARY"
        sudo strip /usr/bin/${coinwallet}
        coinwalletmv=true
    fi

    if [[ -n "$COINQTFIND" ]]; then
        echo -e "$GREEN  QT moving to => /usr/bin/$NC$YELLOW${coinqt} $NC"
        mhp_install_coin_binary "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}/src/${coinqt}" "${coinqt}" "qt" || { return 1 2>/dev/null || exit 1; }
        coinqt="$MHP_INSTALLED_BINARY"
        sudo strip /usr/bin/${coinqt}
        coinqtmv=true
    fi

    echo
    echo -e "$CYAN --------------------------------------------------------------------------------------- $NC"
    echo
fi

if [[ "$YIIMPCONF" == "true" ]]; then
    # Make the new wallet folder have user paste the coin.conf and finally start the daemon
    if [[ ! -e "$STORAGE_ROOT/wallets" ]]; then
        sudo mkdir -p $STORAGE_ROOT/wallets
    fi

    sudo setfacl -m u:${USERSERVER}:rwx $STORAGE_ROOT/wallets
    mkdir -p "$STORAGE_ROOT/wallets/.${coin,,}"

    if [[ "$coinwalletmv" == "true" ]]; then
        echo
        clear
        echo -e "$CYAN ----------------------------------------------------------------------------------- 	$NC"
        echo -e "$GREEN   Creating WALLET.DAT to => ${STORAGE_ROOT}/wallets/.${coin,,}/wallet.dat          $NC"
        echo -e "$CYAN ----------------------------------------------------------------------------------- 	$NC"
        echo
        "${coinwallet}" -datadir="${STORAGE_ROOT}/wallets/.${coin,,}" -wallet=. create
    fi
fi

if [[ ("$DAEMOND" != "true") ]]; then
    echo
    clear
    echo -e "$CYAN --------------------------------------------------------------------------------------- 	$NC"
    echo -e "$GREEN   Adding dedicated port to ${coin^^}$NC"
    echo -e "$CYAN --------------------------------------------------------------------------------------- 	$NC"
    echo

    addport "CREATECOIN" "${coin^^}" "${coinalgo}"

    ADDPORTCONF="$STORAGE_ROOT/daemon_builder/.addport.cnf"

    # addport must create this file with the selected
    # algorithm, port and Stratum binary.
    if [[ -f "$ADDPORTCONF" ]]; then

        source "$ADDPORTCONF"

        print_success "Dedicated Stratum information loaded"
        print_info "Coin           : ${coin^^}"

        if [[ -n "${COINALGO:-}" ]]; then
            print_info "Algorithm      : ${COINALGO}"
        fi

        if [[ -n "${COINPORT:-}" ]]; then
            print_info "Port           : ${COINPORT}"
        fi

        if [[ -n "${STRATUMBINARY:-}" ]]; then
            print_info "Stratum binary : ${STRATUMBINARY}"
        fi

    else

        print_error "Stratum configuration information was not generated."
        print_error "Missing file: ${ADDPORTCONF}"
        print_info "Installation cannot continue safely."

        exit 1
    fi

    # ============================================================
    # MEGAHASHPOOL - INTERACTIVE WALLET CONFIGURATION
    # ============================================================

    if [[ "${YIIMPCONF}" == "true" ]]; then
        COIN_WALLET_NAME="${coin,,}"
        COIN_WALLET_DIR="${STORAGE_ROOT}/wallets/.${COIN_WALLET_NAME}"
    else
        COIN_WALLET_NAME="${coin,,}"
        COIN_WALLET_DIR="${absolutepath}/wallets/.${COIN_WALLET_NAME}"
    fi

    COIN_WALLET_CONF="${COIN_WALLET_DIR}/${COIN_WALLET_NAME}.conf"

    # YiiMP daemons run under crypto-data.
    # Wallet directories/configs must therefore belong to crypto-data.
    if [[ "${YIIMPCONF}" == "true" ]]; then
        CONF_OWNER="crypto-data"
    else
        CONF_OWNER="${USERSERVER:-$USER}"
    fi

    if ! id "${CONF_OWNER}" >/dev/null 2>&1; then
        print_error "Wallet owner user does not exist: ${CONF_OWNER}"
        exit 1
    fi

    CONF_GROUP="$(id -gn "${CONF_OWNER}")"

    print_header "Wallet Configuration"
    print_status "Preparing configuration for ${coin^^}..."
    print_info "Wallet dir    : ${COIN_WALLET_DIR}"
    print_info "Config file   : ${COIN_WALLET_CONF}"

    sudo install -d \
        -o "${CONF_OWNER}" \
        -g "${CONF_GROUP}" \
        -m 750 \
        "${COIN_WALLET_DIR}"

    # Never overwrite an existing configuration automatically.
    if [[ ! -f "${COIN_WALLET_CONF}" ]]; then
        sudo -u "${CONF_OWNER}" touch "${COIN_WALLET_CONF}"
    fi

    sudo chown "${CONF_OWNER}:${CONF_GROUP}" "${COIN_WALLET_CONF}"
    sudo chmod 600 "${COIN_WALLET_CONF}"

    TMP_CONF="$(mktemp)"
    TMP_CONF_NEW="${TMP_CONF}.new"

    # Load existing configuration into the integrated editor.
    sudo cat "${COIN_WALLET_CONF}" > "${TMP_CONF}"

    dialog \
        --colors \
        --backtitle "MegaHashPool DaemonBuilder" \
        --title "Configure ${coin^^}" \
        --ok-label "CONTINUE" \
        --msgbox "\
The daemon binaries have been installed.

Now configure the ${coin^^} wallet.

Configuration file:

\Zb\Z3${COIN_WALLET_CONF}\Zn

On the next screen you can paste or edit the configuration
directly inside DaemonBuilder.

You do NOT need to use nano.

After saving, installation will continue automatically." \
        19 82

    while true; do

        : > "${TMP_CONF_NEW}"

        if dialog \
            --stdout \
            --colors \
            --backtitle "MegaHashPool DaemonBuilder" \
            --title "${coin^^} - Wallet Configuration" \
            --ok-label "SAVE AND CONTINUE" \
            --cancel-label "CANCEL" \
            --editbox "${TMP_CONF}" \
            30 100 > "${TMP_CONF_NEW}"
        then

            if [[ ! -s "${TMP_CONF_NEW}" ]]; then

                dialog \
                    --backtitle "MegaHashPool DaemonBuilder" \
                    --title "Configuration required" \
                    --msgbox "\
The configuration is empty.

Paste the configuration generated/configured for ${coin^^}
before continuing." \
                    10 70

                continue
            fi

            sudo install \
                -o "${CONF_OWNER}" \
                -g "${CONF_GROUP}" \
                -m 600 \
                "${TMP_CONF_NEW}" \
                "${COIN_WALLET_CONF}"

            cp "${TMP_CONF_NEW}" "${TMP_CONF}"

            break

        else

            # If a valid existing configuration already exists,
            # allow the user to keep it.
            if [[ -s "${TMP_CONF}" ]]; then

                if dialog \
                    --backtitle "MegaHashPool DaemonBuilder" \
                    --title "${coin^^} Configuration" \
                    --yes-label "KEEP AND CONTINUE" \
                    --no-label "EDIT AGAIN" \
                    --yesno "\
An existing configuration is already present:

${COIN_WALLET_CONF}

Do you want to keep it and continue installation?" \
                    13 78
                then
                    break
                else
                    continue
                fi

            else

                dialog \
                    --backtitle "MegaHashPool DaemonBuilder" \
                    --title "Configuration required" \
                    --msgbox "\
No configuration has been saved yet.

The installer cannot continue with an empty wallet configuration." \
                    10 72
            fi
        fi
    done

    rm -f "${TMP_CONF}" "${TMP_CONF_NEW}"

    sudo chown "${CONF_OWNER}:${CONF_GROUP}" "${COIN_WALLET_CONF}"
    sudo chmod 600 "${COIN_WALLET_CONF}"

    print_success "${coin^^} wallet configuration saved"
    print_info "Config file   : ${COIN_WALLET_CONF}"
    print_status "Continuing installation..."

    cd "$STORAGE_ROOT/daemon_builder"

fi

# ============================================================
# MEGAHASHPOOL - REQUIRED DAEMON VERIFICATION
# ============================================================

EXPECTED_DAEMON="/usr/bin/${coind}"

if [[ ! -x "${EXPECTED_DAEMON}" ]]; then
    echo
    print_error "Required daemon binary is missing"
    print_error "Expected: ${EXPECTED_DAEMON}"
    print_info "The installation cannot continue without the coin daemon."
    print_info "CLI/TX/Wallet binaries alone are not sufficient for YiiMP."
    echo

    exit 1
fi

print_success "Required daemon verified: ${EXPECTED_DAEMON}"


# ============================================================
# MEGAHASHPOOL - START DAEMON
# ============================================================

print_divider
print_header "Starting Daemon"
print_status "Initializing ${coin^^} daemon..."

DAEMON_START_OK=true
DAEMON_AUTOSTART_OK=false

if [[ "${YIIMPCONF}" == "true" ]]; then

    if sudo -u crypto-data "/usr/bin/${coind}" \
        -datadir="${STORAGE_ROOT}/wallets/.${coin,,}" \
        -conf="${coin,,}.conf" \
        -daemon \
        -shrinkdebugfile
    then
        print_success "${coin^^} daemon start command completed"
    else
        DAEMON_START_OK=false
        print_error "Could not start ${coin^^} daemon"
    fi

    # --------------------------------------------------------
    # Register daemon autostart only when daemon start succeeded
    # --------------------------------------------------------
    if [[ "${DAEMON_START_OK}" == "true" ]]; then

        print_status "Registering ${coin^^} daemon for autostart as crypto-data..."

        DAEMON_BOOT_LOG="/var/log/${coin,,}-daemon-boot.log"

        sudo touch "${DAEMON_BOOT_LOG}"
        sudo chown crypto-data:crypto-data "${DAEMON_BOOT_LOG}"
        sudo chmod 664 "${DAEMON_BOOT_LOG}"

        # Remove legacy entry from current user's crontab.
        (
            crontab -l 2>/dev/null |
            grep -v "/usr/bin/${coind} -datadir=${STORAGE_ROOT}/wallets/.${coin,,}" |
            grep -v "${coind} -datadir=${STORAGE_ROOT}/wallets/.${coin,,}"
        ) | crontab - 2>/dev/null || true

        # Remove previous canonical entry.
        (
            sudo -u crypto-data crontab -l 2>/dev/null |
            grep -v "/usr/bin/${coind} -datadir=${STORAGE_ROOT}/wallets/.${coin,,}"
        ) | sudo -u crypto-data crontab - 2>/dev/null || true

        # Install canonical entry.
        (
            sudo -u crypto-data crontab -l 2>/dev/null
            echo "@reboot sleep 30 && /usr/bin/${coind} -datadir=${STORAGE_ROOT}/wallets/.${coin,,} -conf=${coin,,}.conf -daemon -shrinkdebugfile >> ${DAEMON_BOOT_LOG} 2>&1"
        ) | sudo -u crypto-data crontab -

        if sudo -u crypto-data crontab -l 2>/dev/null |
            grep -Fq "/usr/bin/${coind} -datadir=${STORAGE_ROOT}/wallets/.${coin,,}"
        then
            DAEMON_AUTOSTART_OK=true
            print_success "${coin^^} daemon registered for autostart"
        else
            print_warning "Daemon started, but autostart registration could not be verified"
        fi
    fi

else
    print_info "Automatic daemon start skipped: YiiMP configuration is not enabled"
fi


# ============================================================
# MEGAHASHPOOL - FINAL INSTALLATION SUMMARY
# ============================================================

clear
echo

if command -v figlet >/dev/null 2>&1; then
    figlet -f slant -w 100 "    DaemonBuilder" | lolcat
fi

echo

print_header "Installation Summary"

if [[ "${DAEMOND}" == "true" ]]; then
    print_success "Daemon binaries for ${coind::-1} updated"
else
    print_success "Daemon binaries for ${coind::-1} installed"
fi

print_divider


# ------------------------------------------------------------
# Installed components
# ------------------------------------------------------------

print_header "Installed Components"

if [[ "${coindmv}" == "true" ]]; then
    print_info "Daemon       : ${MAGENTA}${coind}${NC}"
    print_info "Location     : ${YELLOW}/usr/bin/${coind}${NC}"
fi

if [[ "${coinclimv}" == "true" ]]; then
    print_info "CLI Tool     : ${MAGENTA}${coincli}${NC}"
    print_info "Location     : ${YELLOW}/usr/bin/${coincli}${NC}"
fi

if [[ "${cointxmv}" == "true" ]]; then
    print_info "TX Tool      : ${MAGENTA}${cointx}${NC}"
    print_info "Location     : ${YELLOW}/usr/bin/${cointx}${NC}"
fi

if [[ "${coinutilmv}" == "true" ]]; then
    print_info "Utility Tool : ${MAGENTA}${coinutil}${NC}"
    print_info "Location     : ${YELLOW}/usr/bin/${coinutil}${NC}"
fi

if [[ "${coinhashmv}" == "true" ]]; then
    print_info "Hash Tool    : ${MAGENTA}${coinhash}${NC}"
    print_info "Location     : ${YELLOW}/usr/bin/${coinhash}${NC}"
fi

if [[ "${coinwalletmv}" == "true" ]]; then
    print_info "Wallet Tool  : ${MAGENTA}${coinwallet}${NC}"
    print_info "Location     : ${YELLOW}/usr/bin/${coinwallet}${NC}"
fi

print_divider


# ------------------------------------------------------------
# Coin configuration
# ------------------------------------------------------------

print_header "Coin Configuration"

print_info "Symbol       : ${MAGENTA}${coin^^}${NC}"

if [[ -n "${COINALGO:-}" ]]; then
    print_info "Algorithm    : ${MAGENTA}${COINALGO}${NC}"
elif [[ -n "${coinalgo:-}" ]]; then
    print_info "Algorithm    : ${MAGENTA}${coinalgo}${NC}"
fi

if [[ -n "${COINPORT:-}" ]]; then
    print_info "Stratum Port : ${MAGENTA}${COINPORT}${NC}"
fi

if [[ -n "${COIN_WALLET_CONF:-}" ]]; then
    print_info "Wallet Conf  : ${YELLOW}${COIN_WALLET_CONF}${NC}"
fi

print_divider


# ------------------------------------------------------------
# Daemon status
# ------------------------------------------------------------

print_header "Daemon Status"

if [[ "${YIIMPCONF}" == "true" ]]; then

    if [[ "${DAEMON_START_OK}" == "true" ]]; then
        print_success "Daemon start command successful"
    else
        print_error "Daemon failed to start"
    fi

    if [[ "${DAEMON_AUTOSTART_OK}" == "true" ]]; then
        print_success "Autostart enabled for crypto-data"
        print_info "Boot log     : ${YELLOW}${DAEMON_BOOT_LOG}${NC}"
    else
        print_warning "Autostart not verified"
    fi

else
    print_info "Daemon was not started automatically"
fi

print_divider


# ------------------------------------------------------------
# Stratum information
# ------------------------------------------------------------

if [[ -n "${COINPORT:-}" || -n "${COINALGO:-}" ]]; then

    print_header "Stratum Management"

    if [[ -n "${COINPORT:-}" ]]; then
        print_info "Mining Port  : ${MAGENTA}${COINPORT}${NC}"
    fi

    if [[ -n "${STRATUMBINARY:-}" ]]; then
        print_info "Binary       : ${MAGENTA}${STRATUMBINARY}${NC}"
    fi

    if [[ -x "/usr/bin/stratum.${coin,,}" ]]; then
        print_info "Start:"
        echo -e "  ${BLUE}stratum.${coin,,} start ${coin,,}${NC}"

        print_info "Stop:"
        echo -e "  ${BLUE}stratum.${coin,,} stop ${coin,,}${NC}"

        print_info "Restart:"
        echo -e "  ${BLUE}stratum.${coin,,} restart ${coin,,}${NC}"

        print_info "Console:"
        echo -e "  ${BLUE}screen -r ${coin,,}${NC}"

        print_info "Boot log:"
        echo -e "  ${YELLOW}/var/log/stratum-${coin,,}-boot.log${NC}"
    fi

    print_divider
fi


# ============================================================
# CLEANUP - ONLY AFTER ALL INFORMATION HAS BEEN USED
# ============================================================

print_status "Cleaning temporary installation files..."

if [[ -f "$STORAGE_ROOT/daemon_builder/temp_coin_builds/.lastcoin.conf" ]]; then
    sudo rm -f "$STORAGE_ROOT/daemon_builder/temp_coin_builds/.lastcoin.conf"
fi

if [[ -d "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}" ]]; then
    sudo rm -rf "$STORAGE_ROOT/daemon_builder/temp_coin_builds/${coindir}"
fi

if [[ -f "$STORAGE_ROOT/daemon_builder/.daemon_builder.my.cnf" ]]; then
    sudo rm -f "$STORAGE_ROOT/daemon_builder/.daemon_builder.my.cnf"
fi

if [[ -f "${ADDPORTCONF:-}" ]]; then
    sudo rm -f "${ADDPORTCONF}"
fi

print_success "Temporary installation files cleaned"

print_divider


# ============================================================
# REAL END OF INSTALLATION
# ============================================================

if [[ "${YIIMPCONF}" == "true" && "${DAEMON_START_OK}" != "true" ]]; then

    echo -e "$CYAN =========================================================================== $NC"
    echo -e "$RED Installation finished, but the ${coin^^} daemon did NOT start correctly. $NC"
    echo -e "$YELLOW Check the wallet configuration and daemon log before starting Stratum. $NC"
    echo -e "$CYAN =========================================================================== $NC"
    echo

    exit 1

else

    echo -e "$CYAN =========================================================================== $NC"
    echo -e "$GREEN ${coin^^} installation completed successfully! $NC"

    if [[ -n "${COINPORT:-}" ]]; then
        echo -e "$GREEN Stratum port: ${MAGENTA}${COINPORT}${NC}"
    fi

    echo -e "$RED Type ${MAGENTA}daemonbuilder${NC}${RED} at any time to install another coin.${NC}"
    echo -e "$CYAN =========================================================================== $NC"
    echo

    exit 0
fi
