#!/bin/bash
# ReleaseSafe / Debug panic gate.
#
# Build first:
#   zig build -Doptimize=ReleaseSafe
# then:
#   ./tests/difftest/run-safe.sh
#
# This is run.sh + bytecode.sh + zigonly/run.sh against the current Zig
# binary. Default memory limit is 16M (enough to catch panics without the
# full 4-limit sweep). Any abort, panic, stdout/exit-code diff vs C,
# bytecode size drift, or zigonly expected-output mismatch is a fail.
# After this phase, a ReleaseSafe panic is a genuine bug.

set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

LIMITS="${LIMITS:-16M}" "$HERE/run.sh"
status=$?
"$HERE/bytecode.sh"
bstatus=$?
"$HERE/../zigonly/run.sh"
zstatus=$?
if [ "$status" != "0" ] || [ "$bstatus" != "0" ] || [ "$zstatus" != "0" ]; then
  exit 1
fi
