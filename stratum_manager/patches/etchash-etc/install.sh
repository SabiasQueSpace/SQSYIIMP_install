#!/usr/bin/env bash
set -euo pipefail

PKG_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="${SOURCE_ROOT:-/home/crypto-data/yiimp/site/code-stratums/stratum-kawpow-sqs}"
RUNTIME_BINARY="${RUNTIME_BINARY:-/home/crypto-data/yiimp/site/stratum/stratum-ethash-test}"
BACKUP_ROOT="${BACKUP_ROOT:-/home/crypto-data/yiimp/backups}"
ETC_WRAPPER="${ETC_WRAPPER:-/usr/bin/stratum.etc}"

BASE_FILES=(Makefile stratum.cpp stratum.h job.cpp ethash.cpp)
NEW_FILES=(etc_etchash_bridge.c etc_etchash_bridge.h)
ALL_FILES=("${BASE_FILES[@]}" "${NEW_FILES[@]}")

declare -A ORIGINAL_HASH=(
  [Makefile]="06dde065a25e1fc177146cac7ac2ea0e85a12c485809ffbbaa2cbbd934c204b7"
  [stratum.cpp]="1da3f4c2630c4596f8450b37afaa633aa4306fa468bddcdf8f7855f416de1ef0"
  [stratum.h]="31df59ce24cfa351ccd9e3feebb5729d16450f0b79f8ecb372a2a17d4bf4f549"
  [job.cpp]="7c2198d30c99ba4e6fde9cae77fa6cab83391a0b98cd7c8fbd35839fa84c61c9"
  [ethash.cpp]="d44d5ba06e2e3d6ef0e2a5fdf776aa8cf2f88076425e024fe5bd6b7bfaa7545a"
)

declare -A PATCHED_HASH=(
  [Makefile]="d03f77358666a8fa7f15dce2face25e9c1b4f9439eeb11df7948d11633baddca"
  [stratum.cpp]="dd7c5813512c89c524ee456536dc4263ae0b9fd78965ab1a482b42cb86cdb83b"
  [stratum.h]="5a70588d6891c0c3359b454f113e8d65aad3ab7092541acf5568de8357e4511e"
  [job.cpp]="ad5cee18afd5af36b6a558709ef813ea10655fab00973a4029c24b7fc099176b"
  [ethash.cpp]="900f7c0550471335ce265b6796cfa8bfeb5394db808689752d2419361dcead7a"
  [etc_etchash_bridge.c]="89b2a3c341b350f332802db95c31fd957e35c5a2882fa3fc42c54bef394ce5e3"
  [etc_etchash_bridge.h]="138ae19fd8b8675926f38f1ab8c6e0adf363a61b88c124300939c6c18e32fda9"
)

hash_file() { sha256sum "$1" | awk '{print $1}'; }

die() { echo "ERROR: $*" >&2; exit 1; }

has_binary_marker() {
  local file="$1" marker="$2"
  # Avoid `strings | grep -q` under `set -o pipefail`: grep may exit
  # early after a match, causing strings to receive SIGPIPE and making a
  # successful marker check look like a failure.
  LC_ALL=C grep -aF -- "$marker" "$file" >/dev/null 2>&1
}

atomic_install_file() {
  local src="$1" dst="$2" uid="$3" gid="$4" mode="$5"
  local dir tmp
  dir="$(dirname "$dst")"
  mkdir -p "$dir"
  tmp="$(mktemp "$dir/.sqsyiimp-etchash.XXXXXX")"
  if ! install -o "$uid" -g "$gid" -m "$mode" "$src" "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  # Atomic rename works even when another Stratum process is still executing
  # the previous inode. Existing processes keep the old inode; future starts
  # use the new binary.
  if ! mv -f "$tmp" "$dst"; then
    rm -f "$tmp"
    return 1
  fi
}

source_state() {
  local pristine=1 patched=1 f h
  for f in "${BASE_FILES[@]}"; do
    [[ -f "$SOURCE_ROOT/$f" ]] || { echo incompatible; return; }
    h="$(hash_file "$SOURCE_ROOT/$f")"
    [[ "$h" == "${ORIGINAL_HASH[$f]}" ]] || pristine=0
    [[ "$h" == "${PATCHED_HASH[$f]}" ]] || patched=0
  done
  for f in "${NEW_FILES[@]}"; do
    if [[ -e "$SOURCE_ROOT/$f" ]]; then
      pristine=0
      h="$(hash_file "$SOURCE_ROOT/$f")"
      [[ "$h" == "${PATCHED_HASH[$f]}" ]] || patched=0
    else
      patched=0
    fi
  done
  if (( pristine )); then echo pristine
  elif (( patched )); then echo patched
  else echo incompatible
  fi
}

check_common() {
  [[ -d "$SOURCE_ROOT" ]] || die "source root not found: $SOURCE_ROOT"
  [[ -f "$SOURCE_ROOT/third_party/vbc-hash/src/libethash/internal.h" ]] || \
    die "vendored VBC Ethash internal API not found"
  for f in "${ALL_FILES[@]}"; do
    [[ -f "$PKG_DIR/files/$f" ]] || die "package file missing: $f"
    [[ "$(hash_file "$PKG_DIR/files/$f")" == "${PATCHED_HASH[$f]}" ]] || \
      die "package checksum mismatch: $f"
  done
  for x in gcc make cmake sha256sum strings; do
    command -v "$x" >/dev/null || die "required command missing: $x"
  done
}

check_bridge_compile() {
  local tmp
  tmp="$(mktemp -d)"
  if ! gcc -std=gnu11 -O2 -Wall -Wextra -Werror \
      -I"$SOURCE_ROOT" -I"$SOURCE_ROOT/third_party/vbc-hash/src" \
      -c "$PKG_DIR/files/etc_etchash_bridge.c" -o "$tmp/etc_etchash_bridge.o"; then
    rm -rf "$tmp"
    die "Etchash bridge compile check failed"
  fi
  rm -rf "$tmp"
}

show_check() {
  check_common
  local state
  state="$(source_state)"
  echo "Source:          $SOURCE_ROOT"
  echo "Runtime binary: $RUNTIME_BINARY"
  echo "Source state:    $state"
  if [[ -x "$ETC_WRAPPER" ]]; then
    echo "ETC Stratum:     $($ETC_WRAPPER status 2>&1 || true)"
  else
    echo "ETC Stratum:     wrapper not found ($ETC_WRAPPER)"
  fi
  if [[ -f "$RUNTIME_BINARY" ]]; then
    echo "Runtime SHA256:  $(hash_file "$RUNTIME_BINARY")"
  else
    echo "Runtime SHA256:  not present"
  fi
  check_bridge_compile
  echo "Bridge compile:  OK"
  case "$state" in
    pristine) echo "CHECK OK: source matches the uploaded pre-Etchash snapshot." ;;
    patched)  echo "CHECK OK: Etchash source patch is already installed." ;;
    *) die "source differs from both the expected original and patched versions; nothing changed" ;;
  esac
}

restore_backup() {
  local backup="$1" f
  [[ -d "$backup/source" ]] || die "invalid backup directory: $backup"
  for f in "${BASE_FILES[@]}"; do
    [[ -f "$backup/source/$f" ]] || die "backup file missing: $f"
    cp -a "$backup/source/$f" "$SOURCE_ROOT/$f"
  done
  for f in "${NEW_FILES[@]}"; do
    rm -f "$SOURCE_ROOT/$f"
  done
  if [[ -f "$backup/runtime/stratum-ethash-test" ]]; then
    local rt_uid rt_gid rt_mode
    if [[ -f "$RUNTIME_BINARY" ]]; then
      rt_uid="$(stat -c %u "$RUNTIME_BINARY")"
      rt_gid="$(stat -c %g "$RUNTIME_BINARY")"
      rt_mode="$(stat -c %a "$RUNTIME_BINARY")"
    else
      rt_uid="$(stat -c %u "$backup/runtime/stratum-ethash-test")"
      rt_gid="$(stat -c %g "$backup/runtime/stratum-ethash-test")"
      rt_mode="$(stat -c %a "$backup/runtime/stratum-ethash-test")"
    fi
    atomic_install_file "$backup/runtime/stratum-ethash-test" "$RUNTIME_BINARY" "$rt_uid" "$rt_gid" "$rt_mode" ||
      die "unable to restore runtime binary atomically: $RUNTIME_BINARY"
  fi
  echo "ROLLBACK OK: restored from $backup"
}

if [[ "${1:-}" == "--check" ]]; then
  show_check
  exit 0
fi

if [[ "${1:-}" == "--rollback" ]]; then
  [[ $# -eq 2 ]] || die "usage: $0 --rollback /path/to/backup"
  [[ $EUID -eq 0 ]] || die "rollback must be run as root (sudo)"
  restore_backup "$2"
  exit 0
fi

[[ $# -eq 0 ]] || die "usage: $0 [--check | --rollback BACKUP_DIR]"
[[ $EUID -eq 0 ]] || die "installation must be run as root (sudo)"
check_common

state="$(source_state)"
[[ "$state" == pristine ]] || {
  if [[ "$state" == patched ]]; then
    die "Etchash source patch is already installed; use --check"
  fi
  die "source differs from the uploaded pre-Etchash snapshot; nothing changed"
}

if [[ -x "$ETC_WRAPPER" ]]; then
  status="$($ETC_WRAPPER status 2>&1 || true)"
  if grep -qi 'RUNNING' <<<"$status"; then
    die "ETC Stratum is running. Stop it first with: $ETC_WRAPPER stop"
  fi
fi

check_bridge_compile

TS="$(date +%Y%m%d-%H%M%S)"
BACKUP="$BACKUP_ROOT/stratum-etchash-$TS"
mkdir -p "$BACKUP/source" "$BACKUP/runtime"

for f in "${BASE_FILES[@]}"; do
  cp -a "$SOURCE_ROOT/$f" "$BACKUP/source/$f"
done
if [[ -f "$RUNTIME_BINARY" ]]; then
  cp -a "$RUNTIME_BINARY" "$BACKUP/runtime/stratum-ethash-test"
fi
{
  echo "created=$TS"
  echo "source=$SOURCE_ROOT"
  echo "runtime=$RUNTIME_BINARY"
  echo "package=MegaHashPool-Stratum-Etchash-ETC-v1.0.1"
} > "$BACKUP/metadata.txt"

restore_on_failure() {
  echo "INSTALL FAILED: restoring source/runtime from $BACKUP" >&2
  for f in "${BASE_FILES[@]}"; do
    cp -a "$BACKUP/source/$f" "$SOURCE_ROOT/$f" || true
  done
  for f in "${NEW_FILES[@]}"; do
    rm -f "$SOURCE_ROOT/$f" || true
  done
  if [[ -f "$BACKUP/runtime/stratum-ethash-test" ]]; then
    local rt_uid rt_gid rt_mode
    if [[ -f "$RUNTIME_BINARY" ]]; then
      rt_uid="$(stat -c %u "$RUNTIME_BINARY")"
      rt_gid="$(stat -c %g "$RUNTIME_BINARY")"
      rt_mode="$(stat -c %a "$RUNTIME_BINARY")"
    else
      rt_uid="$(stat -c %u "$BACKUP/runtime/stratum-ethash-test")"
      rt_gid="$(stat -c %g "$BACKUP/runtime/stratum-ethash-test")"
      rt_mode="$(stat -c %a "$BACKUP/runtime/stratum-ethash-test")"
    fi
    atomic_install_file "$BACKUP/runtime/stratum-ethash-test" "$RUNTIME_BINARY" "$rt_uid" "$rt_gid" "$rt_mode" || true
  fi
}

src_uid="$(stat -c %u "$SOURCE_ROOT/ethash.cpp")"
src_gid="$(stat -c %g "$SOURCE_ROOT/ethash.cpp")"

for f in "${BASE_FILES[@]}"; do
  mode="$(stat -c %a "$SOURCE_ROOT/$f")"
  install -o "$src_uid" -g "$src_gid" -m "$mode" "$PKG_DIR/files/$f" "$SOURCE_ROOT/$f"
done
for f in "${NEW_FILES[@]}"; do
  install -o "$src_uid" -g "$src_gid" -m 0644 "$PKG_DIR/files/$f" "$SOURCE_ROOT/$f"
done

if ! (cd "$SOURCE_ROOT" && make buildonly -j"$(nproc)"); then
  restore_on_failure
  die "Stratum build failed; original source/runtime restored"
fi

BUILT="$SOURCE_ROOT/stratum"
if [[ ! -x "$BUILT" ]] || \
   ! has_binary_marker "$BUILT" 'etchash' || \
   ! has_binary_marker "$BUILT" 'Algorithm engine selected: ETCHASH (Ethereum Classic ECIP-1099)'; then
  restore_on_failure
  die "built binary does not contain the Etchash engine markers; restored"
fi

mkdir -p "$(dirname "$RUNTIME_BINARY")"
if [[ -f "$RUNTIME_BINARY" ]]; then
  rt_uid="$(stat -c %u "$RUNTIME_BINARY")"
  rt_gid="$(stat -c %g "$RUNTIME_BINARY")"
  rt_mode="$(stat -c %a "$RUNTIME_BINARY")"
else
  rt_uid="$src_uid"; rt_gid="$src_gid"; rt_mode=0755
fi

if ! atomic_install_file "$BUILT" "$RUNTIME_BINARY" "$rt_uid" "$rt_gid" "$rt_mode"; then
  restore_on_failure
  die "runtime deployment failed; restored"
fi

if ! has_binary_marker "$RUNTIME_BINARY" 'Algorithm engine selected: ETCHASH (Ethereum Classic ECIP-1099)'; then
  restore_on_failure
  die "runtime verification failed; restored"
fi

cat <<MSG
INSTALL OK: Etchash/ECIP-1099 support compiled and deployed.

Backup:
  $BACKUP

Runtime:
  $RUNTIME_BINARY

IMPORTANT: ETC Stratum was NOT started automatically.
Wait until Core-Geth finishes syncing:
  /usr/bin/ethereumclassic-rpc eth_syncing

Only when the result is false, start and inspect ETC:
  /usr/bin/stratum.etc start
  sleep 2
  /usr/bin/stratum.etc status
  tail -n 80 /var/log/stratum-etc.log

Expected engine marker:
  Algorithm engine selected: ETCHASH (Ethereum Classic ECIP-1099)

Rollback if needed:
  sudo bash "$PKG_DIR/install.sh" --rollback "$BACKUP"
MSG
