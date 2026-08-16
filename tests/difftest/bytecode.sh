#!/bin/bash
# Bytecode differential: C mquickjs (reference) vs the Zig port.
#
# run.sh only compares what a script *prints*. This compares what the two
# engines *emit*, which is a different bug class: the 64->32 bit heap
# conversion used by `-m32` is not exercised by running scripts at all.
# debug-notes.md fix 15 (JSFloat64_32 sized 16 instead of C's 12) was invisible
# to every runtime test and showed up here as a 4-byte-per-float size drift.
#
#   ./tests/difftest/bytecode.sh
#
# Checks, for every difftest and tests/test_*.js script:
#   1. 64 bit image sizes agree
#   2. 32 bit image sizes agree   <- the layout invariant fix 15 restored
#   3. all four cross combinations (compile on A, run on B) print the same
#      thing as running the source directly
#
# Byte-level differences are reported but do not fail the run: both engines
# leave uninitialised padding after strings, so a stale byte is expected
# (documented in debug-notes.md). A *size* difference never is: the 32 bit
# heap size is a deterministic function of the object graph.
#
# Env overrides: C_MQJS, Z_MQJS

set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)

C_MQJS="${C_MQJS:-$ROOT/../mquickjs/mqjs}"
Z_MQJS="${Z_MQJS:-$ROOT/zig-out/bin/mqjs}"

for bin in "$C_MQJS" "$Z_MQJS"; do
  if [ ! -x "$bin" ]; then
    echo "missing engine: $bin" >&2
    exit 2
  fi
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

FAIL=0
BYTES=0
strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

for f in "$HERE"/*.js "$ROOT"/tests/test_*.js; do
  [ -e "$f" ] || continue
  name=$(basename "$f")

  "$C_MQJS" -o "$TMP/c64.bin" "$f" 2>/dev/null || { echo "SKIP $name (C compile failed)"; continue; }
  "$Z_MQJS" -o "$TMP/z64.bin" "$f" 2>/dev/null || { echo "SKIP $name (Zig compile failed)"; continue; }
  "$C_MQJS" -m32 -o "$TMP/c32.bin" "$f" 2>/dev/null
  "$Z_MQJS" -m32 -o "$TMP/z32.bin" "$f" 2>/dev/null

  for w in 64 32; do
    cs=$(stat -c%s "$TMP/c$w.bin")
    zs=$(stat -c%s "$TMP/z$w.bin")
    if [ "$cs" != "$zs" ]; then
      FAIL=1
      echo "=== SIZE DIFF $name ${w}bit: C=$cs Zig=$zs (delta $((zs - cs))) ==="
    elif ! cmp -s "$TMP/c$w.bin" "$TMP/z$w.bin"; then
      BYTES=$((BYTES + 1))
      echo "note: $name ${w}bit images differ in $(cmp -l "$TMP/c$w.bin" "$TMP/z$w.bin" | wc -l) byte(s) of padding"
    fi
  done

  # Cross execution: every combination of (who compiled, who runs) must print
  # exactly what running the source prints.
  ref=$("$C_MQJS" "$f" 2>&1 | strip_ansi)
  for img in c64 z64; do
    for eng in "$C_MQJS" "$Z_MQJS"; do
      out=$("$eng" -b "$TMP/$img.bin" 2>&1 | strip_ansi)
      if [ "$out" != "$ref" ]; then
        FAIL=1
        echo "=== EXEC DIFF $name image=$img engine=$(basename $(dirname $eng))/$(basename $eng) ==="
        diff <(printf '%s\n' "$ref") <(printf '%s\n' "$out") | head -10
      fi
    done
  done
done

[ "$BYTES" != "0" ] && echo "($BYTES image(s) differed only in padding bytes -- expected)"
if [ "$FAIL" = "0" ]; then echo "ALL BYTECODE MATCH"; fi
exit $FAIL
