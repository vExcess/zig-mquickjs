#!/bin/bash
# Independent expected-output suite. No C reference. After fix 22, also
# covers default-arg regexp re-lex.
#
#   zig build -Doptimize=ReleaseFast
#   ./tests/oracle/run.sh
#
# Env overrides: Z_MQJS, LIMITS

set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)

Z_MQJS="${Z_MQJS:-$ROOT/zig-out/bin/mqjs}"
LIMITS="${LIMITS:-16M}"

if [ ! -x "$Z_MQJS" ]; then
  echo "missing engine: $Z_MQJS" >&2
  echo "build with 'zig build -Doptimize=ReleaseFast'" >&2
  exit 2
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

FAIL=0
for f in "$HERE"/*.js; do
  [ -e "$f" ] || continue
  name=$(basename "$f")
  exp="${f%.js}.expected"
  if [ ! -f "$exp" ]; then
    FAIL=1
    echo "=== MISSING expected file for $name ==="
    continue
  fi
  expected=$(cat "$exp")

  for lim in $LIMITS; do
    zout=$("$Z_MQJS" --memory-limit "$lim" "$f" 2>&1 | strip_ansi); zrc=${PIPESTATUS[0]}
    if [ "$zrc" != "0" ] || [ "$zout" != "$expected" ]; then
      FAIL=1
      echo "=== DIFF $name @ $lim (Zig rc=$zrc) ==="
      diff <(printf '%s\n' "$expected") <(printf '%s\n' "$zout") | head -40
      echo
    fi

    case "$zout" in
      *"DONE $name"*) ;;
      *) FAIL=1
         echo "=== TRUNCATED $name @ $lim (never reached DONE) ==="
         printf '%s\n' "$zout" | tail -3; echo ;;
    esac

    case "$zout" in
      *FAIL*) FAIL=1
         echo "=== SELF-CHECK FAIL $name @ $lim ===" ;;
    esac

    "$Z_MQJS" -o "$TMP/z.bin" "$f" >/dev/null 2>&1 || {
      FAIL=1
      echo "=== COMPILE FAIL $name ==="
      continue
    }
    bout=$("$Z_MQJS" -b "$TMP/z.bin" 2>&1 | strip_ansi); brc=${PIPESTATUS[0]}
    if [ "$brc" != "0" ] || [ "$bout" != "$expected" ]; then
      FAIL=1
      echo "=== BYTECODE DIFF $name (Zig rc=$brc) ==="
      diff <(printf '%s\n' "$expected") <(printf '%s\n' "$bout") | head -40
      echo
    fi
  done
done

if [ "$FAIL" = "0" ]; then echo "ALL ORACLE MATCH"; fi
exit $FAIL
