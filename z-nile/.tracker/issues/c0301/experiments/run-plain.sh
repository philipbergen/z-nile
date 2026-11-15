#!/usr/bin/env bash
# run specs in the scratch prototype in a plain (non-dispatched) environment
P=${C0301_DIR:-$(cat /tmp/c0301-proto-path)/repo} # the scratch clone (Unknowns), never a checkout
cd "$P/z-nile" || exit 2
CLEAN_PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '/z-nile/bin$' | paste -sd: -)
exec env -i HOME="$HOME" USER="$USER" TMPDIR="$TMPDIR" PATH="$CLEAN_PATH" TERM=dumb lune run tests/run -- "$@"
