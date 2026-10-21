#!/usr/bin/env bash
# Acceptance checks for c0113. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home: the root
# c0115's sequestered specs, which this superseded item's checks reuse: in c0115's folder before its `done`, promoted after
C="$("$ZN_ROOT/zn" find c0115)/acceptance"
[[ -d $C ]] || C="$PWD/tests/acceptance/c0115"

check "AC1: z-nile/README.md, which supersedes this page, covers each of its asks" lune run tests/run -- "$C/readme.spec.luau"
check "AC2: the page this item added, .claude/README.md, is gone" bash -c '! git ls-files --error-unmatch .claude/README.md >/dev/null 2>&1'

finish
