#!/usr/bin/env bash

############################################################
# SQSYIIMP Installer
# SabiasQue.Space
#
# Public bootstrap installer for SQSYIIMP.
#
# Run with:
#
# curl -fsSL https://raw.githubusercontent.com/SabiasQueSpace/SQSYIIMP_install/main/install.sh | bash
#
############################################################

set -Eeuo pipefail

PROJECT_NAME="SQSYIIMP"
PROJECT_SUBTITLE="SabiasQue.Space"

REPO_URL="${SQSYIIMP_REPO_URL:-https://github.com/SabiasQueSpace/SQSYIIMP_install.git}"
# Leave TAG empty to install the latest stable vX.Y.Z release. A caller can
# still select an exact release explicitly, for example TAG=v1.0.1.
TAG="${TAG:-}"
INSTALL_DIR="${SQSYIIMP_INSTALL_DIR:-$HOME/sqsyiimp}"
VERSION_FILE="/etc/yiimpoolversion.conf"

SUDO=""

log_info() {
    echo "[${PROJECT_NAME}] $1"
}

log_warn() {
    echo "[${PROJECT_NAME}] WARNING: $1" >&2
}

log_error() {
    echo "[${PROJECT_NAME}] ERROR: $1" >&2
}

fail() {
    log_error "$1"
    exit 1
}

setup_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        SUDO=""
        return
    fi

    command -v sudo >/dev/null 2>&1 \
        || fail "sudo is required"

    SUDO="sudo"
}

install_git() {
    if command -v git >/dev/null 2>&1; then
        log_info "Git is already installed."
        return
    fi

    log_info "Git not found; installing Git..."

    $SUDO apt-get -q update

    DEBIAN_FRONTEND=noninteractive \
        $SUDO apt-get -q install -y \
        git \
        ca-certificates \
        < /dev/null

    log_info "Git installed."
}

remote_tag_exists() {
    local tag="${1:-$TAG}"

    [ -n "$tag" ] || return 1

    git ls-remote \
        --exit-code \
        --tags \
        "$REPO_URL" \
        "refs/tags/$tag" \
        >/dev/null 2>&1
}

latest_stable_tag() {
    git ls-remote \
        --tags \
        --refs \
        "$REPO_URL" \
        'refs/tags/v*' \
        2>/dev/null |
        awk -F/ '$3 ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/ {print $3}' |
        sort -V |
        tail -n 1
}

resolve_release_tag() {
    local latest=""

    if [ -n "$TAG" ]; then
        remote_tag_exists "$TAG" \
            || fail "Requested release tag was not found: $TAG"

        log_info "Selected release: $TAG"
        return
    fi

    log_info "Detecting the latest stable SQSYIIMP release..."
    latest="$(latest_stable_tag)"

    [ -n "$latest" ] \
        || fail "No stable SQSYIIMP release tag matching vX.Y.Z was found"

    TAG="$latest"
    log_info "Latest stable release: $TAG"
}

remote_default_branch() {
    git ls-remote --symref "$REPO_URL" HEAD 2>/dev/null \
        | awk '/^ref:/ {
            sub("refs/heads/", "", $2)
            print $2
            exit
        }'
}

ensure_repository_access() {
    git ls-remote \
        "$REPO_URL" \
        HEAD \
        >/dev/null 2>&1 \
        || fail "Unable to access repository: $REPO_URL"
}

clone_repository() {
    local default_branch=""

    ensure_repository_access

    default_branch="$(remote_default_branch)"

    [ -n "$default_branch" ] \
        || fail "Unable to determine the repository default branch"

    log_info "Cloning $default_branch and installing release $TAG..."

    git clone \
        --depth 1 \
        --branch "$default_branch" \
        "$REPO_URL" \
        "$INSTALL_DIR" \
        < /dev/null \
        || fail "Unable to clone repository branch: $default_branch"

    git -C "$INSTALL_DIR" fetch \
        --depth 1 \
        --force \
        origin \
        "refs/tags/$TAG:refs/tags/$TAG" \
        < /dev/null \
        || fail "Unable to fetch release tag: $TAG"

    # Keep the checkout on the normal branch so the built-in updater can
    # fast-forward it to a future release without encountering detached HEAD.
    git -C "$INSTALL_DIR" reset --hard "$TAG" >/dev/null \
        || fail "Unable to position $default_branch at release $TAG"
}

update_repository() {
    local current_remote=""
    local default_branch=""

    current_remote="$(
        git -C "$INSTALL_DIR" \
            config --get remote.origin.url \
            2>/dev/null || true
    )"

    if [ "$current_remote" != "$REPO_URL" ]; then
        log_error "Existing checkout uses another repository:"
        echo "  $current_remote" >&2

        log_error "Expected repository:"
        echo "  $REPO_URL" >&2

        log_error "The existing checkout was not modified."
        exit 1
    fi

    if [ -n "$(
        git -C "$INSTALL_DIR" status --porcelain
    )" ]; then
        log_warn "Local modifications detected in $INSTALL_DIR."

        git -C "$INSTALL_DIR" status --short

        fail "Automatic update stopped to protect local changes"
    fi

    default_branch="$(remote_default_branch)"

    [ -n "$default_branch" ] \
        || fail "Unable to determine the repository default branch"

    log_info "Updating checkout to release $TAG on branch $default_branch..."

    git -C "$INSTALL_DIR" fetch \
        --depth 1 \
        --force \
        --prune \
        origin \
        "+refs/heads/$default_branch:refs/remotes/origin/$default_branch" \
        "refs/tags/$TAG:refs/tags/$TAG" \
        || fail "Unable to fetch branch $default_branch and release $TAG"

    git -C "$INSTALL_DIR" checkout -q \
        -B "$default_branch" \
        "$TAG" \
        || fail "Unable to position $default_branch at release $TAG"

    git -C "$INSTALL_DIR" branch \
        --set-upstream-to="origin/$default_branch" \
        "$default_branch" \
        >/dev/null \
        || fail "Unable to configure upstream branch origin/$default_branch"
}

prepare_repository() {
    if [ -d "$INSTALL_DIR/.git" ]; then
        log_info "Existing SQSYIIMP checkout found at $INSTALL_DIR"
        update_repository
        return
    fi

    if [ -e "$INSTALL_DIR" ]; then
        fail "Install path exists but is not a Git checkout: $INSTALL_DIR"
    fi

    clone_repository
}

install_launcher() {
    log_info "Installing yiimpool launcher..."

    $SUDO tee /usr/bin/yiimpool >/dev/null <<EOF_LAUNCHER
#!/usr/bin/env bash
set -e

cd "$INSTALL_DIR/install"
exec bash start.sh "\$@"
EOF_LAUNCHER

    $SUDO chmod 755 /usr/bin/yiimpool
}

set_installer_version() {
    echo "VERSION=$TAG" \
        | $SUDO tee "$VERSION_FILE" \
        >/dev/null
}

start_installation() {
    local launcher="$INSTALL_DIR/install/start.sh"

    [ -f "$launcher" ] \
        || fail "Installer launcher not found: $launcher"

    bash -n "$launcher" \
        || fail "Installer launcher contains syntax errors"

    log_info "$PROJECT_SUBTITLE"
    log_info "Starting install/start.sh"

    exec bash "$launcher"
}

main() {
    setup_sudo
    install_git
    resolve_release_tag
    prepare_repository
    install_launcher
    set_installer_version
    start_installation
}

main "$@"
