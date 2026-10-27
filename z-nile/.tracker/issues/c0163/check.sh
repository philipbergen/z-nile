#!/usr/bin/env bash
# Acceptance checks for c0163. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0163 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0163"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# check "AC1: <statement>" lune run tests/run -- "$A/<name>.spec.luau"
check "AC1: a line starting with seven <, > or | then a space or its end, or exactly seven =, is a conflict marker (look-alikes are not); the verdict names each as <path>:<line>, skips an exempted file and names a stale or malformed exemption" lune run tests/run -- "$A/markers.spec.luau"
check "AC2: ./zn markers fails on a committed or staged conflict, naming file and line, skips untracked and binary files, and takes exemptions only from origin/main's z-nile/marker-exemptions.txt" lune run tests/run -- "$A/command.spec.luau"
check "AC3: the gate's marker stage fails --affected and --full alike on a committed marker, naming it, and passes a clean tree" lune run tests/run -- "$A/gate.spec.luau"
check "AC4: the one deps reader fails closed, naming each line of the deps block that is not an edge, a blank line or a # comment, and pickman's architecture meta spec reads the block through it" lune run tests/run -- "$A/deps.spec.luau"
check "AC5: pickman's architecture meta spec passes on today's architecture.md through the deps reader" bash -c 'cd ../pickman && lune run tests/run -- tests/meta/architecture.spec.luau'
check "AC6: the repository has no committed conflict marker outside the exemption list, which starts empty" "$ZN_ROOT/zn" markers

finish
