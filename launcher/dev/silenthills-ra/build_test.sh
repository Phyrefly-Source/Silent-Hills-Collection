#!/bin/sh
# Builds and runs the kit's tests (Linux/macOS, any C99 compiler).
set -e
cd "$(dirname "$0")"
OUT=${TMPDIR:-/tmp}/shra-test
rm -rf "$OUT"; mkdir -p "$OUT/inbox"
${CC:-cc} -std=c99 -D_DEFAULT_SOURCE -O1 -Wall -Ircheevos/include -o "$OUT/test" test/test.c silenthills_ra.c rcheevos/src/runtime/*.c rcheevos/src/util/*.c -lm
"$OUT/test" "$OUT/inbox" "$OUT"
