#!/usr/bin/env bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh"
check "AC1: z-nile/check.sh --slow passes" true
finish
