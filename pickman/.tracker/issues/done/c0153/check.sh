#!/usr/bin/env bash
# Acceptance checks for c0153. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0153 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0153"

check "AC1: plain.check, equalWithin and roundTrip: the one-ulp-off value within 1e-9, NaN never within, sequences 1..n or string-keyed maps only, every refusal says where, roundTrip never raises" lune run tests/run -- "$A/plain.spec.luau"
check "AC2: the five JSON round trips (f0013 snapshot, f0018, f0030, f0032 frame, f0100 drops) are exactly the narrowed files, and their items' check.sh files still run them" lune run tests/run -- "$A/golden.spec.luau"
check "AC3: the five narrowed specs pass" lune run tests/run -- tests/acceptance/f0013/snapshot.spec.luau tests/acceptance/f0018/frame.spec.luau tests/acceptance/f0030/frame.spec.luau tests/acceptance/f0032/frame.spec.luau tests/acceptance/f0100/drops.spec.luau

finish
