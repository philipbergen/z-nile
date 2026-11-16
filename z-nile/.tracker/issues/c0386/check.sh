#!/usr/bin/env bash
# Acceptance checks for c0386. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0386 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0386"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: c0371's promoted spec names the banned env option nowhere, and its grep case still feeds that fixture and expects no finding" \
  lune run tests/run -- "$A/env-fixture.spec.luau"
check "AC2: c0371's promoted check-paths spec passes" lune run tests/run -- tests/acceptance/c0371/check-paths-homes.spec.luau
check "AC3: z-nile's repository fence spec passes" lune run tests/run -- tests/tooling/repo-fence.spec.luau
check "AC4: the fence spec of each of the six game and library homes passes" \
  bash -c '(cd ../pickman && lune run tests/run -- tests/meta/fence.spec.luau) \
    && (cd ../arcade && lune run tests/run -- tests/meta/fence.spec.luau) \
    && (cd ../portal && lune run tests/run -- tests/meta/fence.spec.luau) \
    && (cd ../snake && lune run tests/run -- tests/meta/fence.spec.luau) \
    && (cd ../invaders && lune run tests/run -- tests/meta/fence.spec.luau) \
    && (cd ../asteroids && lune run tests/run -- tests/meta/fence.spec.luau)'
# AC5 reads the branch's own diff of the scan, so another item's allowances in the same raft (c0123's) pass; the
# banned name is written as a bracket expression because the scan reads this file
check "AC5: the branch gives c0371's files no fence allowance or exemption, and keeps env's banned option in the scan's list" \
  bash -c 'd=$(git diff origin/main...HEAD -- tests/tooling/repo-fence.spec.luau) || exit 1
    ! grep -qE "^[+].*c0371" <<<"$d" && ! grep -qE "^-[[:space:]]*\"env -[i]\"," <<<"$d"'

finish
