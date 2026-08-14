#!/usr/bin/env bash

# Path to your actual mqjs binary
MQJS_BIN="../zig-out/bin/mqjs"

# Collect all non-flag arguments (the actual test files)
ARGS=()
for arg in "$@"; do
    case "$arg" in
        -* ) 
            # Ignore any flags passed by eshost/qjs
            ;;
        * ) 
            ARGS+=("$arg") 
            ;;
    esac
done

# Run mqjs with only the file path(s)
exec "$MQJS_BIN" "${ARGS[@]}"