#!/usr/bin/env bash
set -euo pipefail
SRC="${SOURCE_ROOT:-/home/crypto-data/yiimp/site/code-stratums/stratum-kawpow-sqs}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKG="$(cd -- "$HERE/.." && pwd)"
BUILD="${TMPDIR:-/tmp}/mhp-etchash-test-$$"
trap 'rm -rf "$BUILD"' EXIT
mkdir -p "$BUILD"

for x in cmake gcc; do
  command -v "$x" >/dev/null || { echo "ERROR: missing $x" >&2; exit 1; }
done

test -f "$SRC/third_party/vbc-hash/src/libethash/internal.h" || {
  echo "ERROR: VBC ethash source not found under $SRC" >&2
  exit 1
}

cmake -S "$SRC/third_party/vbc-hash" -B "$BUILD/vbc" -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD/vbc" --target ethash -j"$(nproc)"
LIB="$(find "$BUILD/vbc" -name libethash.a -print -quit)"
test -n "$LIB" -a -f "$LIB" || { echo "ERROR: libethash.a not built" >&2; exit 1; }

gcc -std=gnu11 -O2 -Wall -Wextra -Werror \
  -I"$SRC" -I"$PKG/files" -I"$SRC/third_party/vbc-hash/src" \
  "$HERE/test_etchash_bridge.c" \
  "$SRC/vbc_ethash_bridge.c" \
  "$PKG/files/etc_etchash_bridge.c" \
  "$LIB" -lpthread -lm -o "$BUILD/test_etchash_bridge"

"$BUILD/test_etchash_bridge"
