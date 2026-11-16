#!/usr/bin/env bash
# Runs a command with a plain session's environment: no dispatcher git/gh wrapper on PATH, no publish broker (c0352; d0355 is the defect).
P=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '/z-nile/bin$' | paste -sd: -)
exec env -u ZN_PUBLISH_BROKER -u ZN_PUBLISH_TOKEN -u ZN_DISPATCH -u ZN_HEADLESS -u ZN_DISPATCH_DIR -u ZN_REAL_GIT -u ZN_REAL_GH PATH="$P" "$@"
