#!/usr/bin/env bash
# Acceptance checks for c0116. SEQUESTERED: never edit during execution.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh"
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0116"

check "AC1: recombine lists both members and matches their status" lune run tests/run -- "$A/recombine.spec.luau"
check "AC2: recombine refuses mixed types without the usage banner" lune run tests/run -- "$A/recombine.spec.luau"
check "AC3: z-design has no new raft and zz-rules names z-raft" lune run tests/run -- "$A/recombine.spec.luau"
check "AC4: prepared issues can be rafted and readied; an active issue is refused" lune run tests/run -- "$A/recombine.spec.luau"
check "AC5: active and cross-project rafts are refused; review files move" lune run tests/run -- "$A/recombine.spec.luau"

finish
