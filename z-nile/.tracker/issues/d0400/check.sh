#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh"
check "AC1: the watch file names the missed source files" true
finish
