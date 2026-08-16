#!/bin/bash
# Differential test runner: C mquickjs (reference) vs the Zig port.
#
# Any stdout / exit-code divergence is a port bug. This is how the
# negative-input trig bug (debug-notes.md fix 13) was found after three
# static-audit passes missed it.
#
#   ./tests/difftest/run.sh                        # default limits
#   LIMITS="256M 8M" ./tests/difftest/run.sh       # custom limits
#   SLOW=1 ./tests/difftest/run.sh                 # include slow/ (~2 min/run)
#
# Env overrides: C_MQJS, Z_MQJS, LIMITS, SLOW

set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)

C_MQJS="${C_MQJS:-$ROOT/../mquickjs/mqjs}"
Z_MQJS="${Z_MQJS:-$ROOT/zig-out/bin/mqjs}"
LIMITS="${LIMITS:-256M 16M 4M 2M}"

for bin in "$C_MQJS" "$Z_MQJS"; do
  if [ ! -x "$bin" ]; then
    echo "missing engine: $bin" >&2
    echo "build C with 'make -C ../mquickjs', Zig with 'zig build -Doptimize=ReleaseFast'" >&2
    exit 2
  fi
done

files=$(ls "$HERE"/*.js 2>/dev/null)
[ "${SLOW:-0}" = "1" ] && files="$files $(ls "$HERE"/slow/*.js 2>/dev/null)"

FAIL=0
for f in $files; do
  name=$(basename "$f")
  for lim in $LIMITS; do
    # C mqjs colourises errors and the Zig host does not; that cosmetic
    # difference otherwise masks every real diff.
    cout=$("$C_MQJS" --memory-limit "$lim" "$f" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'); crc=${PIPESTATUS[0]}
    zout=$("$Z_MQJS" --memory-limit "$lim" "$f" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'); zrc=${PIPESTATUS[0]}

    if [ "$cout" != "$zout" ] || [ "$crc" != "$zrc" ]; then
      FAIL=1
      echo "=== DIFF $name @ $lim (C rc=$crc, Zig rc=$zrc) ==="
      diff <(printf '%s\n' "$cout") <(printf '%s\n' "$zout") | head -40
      echo
    fi

    # A script that dies early makes matching output meaningless, so every
    # test ends with a DONE sentinel.
    case "$zout" in
      *"DONE $name"*) ;;
      *) FAIL=1
         echo "=== TRUNCATED $name @ $lim (never reached DONE) ==="
         printf '%s\n' "$zout" | tail -3; echo ;;
    esac
  done
done

if [ "$FAIL" = "0" ]; then echo "ALL MATCH"; fi
exit $FAIL
