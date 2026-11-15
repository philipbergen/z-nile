#!/usr/bin/env bash
# runs "$@" without a dispatched step's variables and with z-nile/bin off PATH
args=()
for v in $(compgen -e); do case $v in ZN_*) args+=(-u "$v");; esac; done
PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '/z-nile/bin$' | paste -sd: -)"
exec env "${args[@]}" PATH="$PATH" "$@"
