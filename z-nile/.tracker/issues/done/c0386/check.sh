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
check "AC1: c0371's promoted spec names the banned env option nowhere" lune run tests/run -- "$A/env-fixture.spec.luau"
# the published main AC2 compares against, printed outside `check` (a passing command's output is hidden): a swapped
# origin is review's to catch
echo "AC2 base: $(git -C "$ZN_ROOT" ls-remote --get-url origin) refs/heads/main"
check "AC2: c0371's promoted spec is its merge base with only the fixture entry respelled, byte for byte" \
  python3 "$A/narrow.py" "$ZN_ROOT"
check "AC3: c0371's promoted check-paths spec passes" lune run tests/run -- tests/acceptance/c0371/check-paths-homes.spec.luau
check "AC4: z-nile's repository fence spec passes" lune run tests/run -- tests/tooling/repo-fence.spec.luau
check "AC5: the fence spec of each of the six game and library homes passes" \
  bash -c '(cd ../pickman && lune run tests/run -- tests/meta/fence.spec.luau) \
    && (cd ../arcade && lune run tests/run -- tests/meta/fence.spec.luau) \
    && (cd ../portal && lune run tests/run -- tests/meta/fence.spec.luau) \
    && (cd ../snake && lune run tests/run -- tests/meta/fence.spec.luau) \
    && (cd ../invaders && lune run tests/run -- tests/meta/fence.spec.luau) \
    && (cd ../asteroids && lune run tests/run -- tests/meta/fence.spec.luau)'
# AC6 reads the scan file as it stands, comment lines dropped, so a raft-mate's comment or another file's allowance
# (c0123's) passes; the banned name is written as a bracket expression because the scan reads this file
check "AC6: the scan still lists env's banned option, and no allowance or exemption key names c0371's spec files" \
  bash -c 'f=tests/tooling/repo-fence.spec.luau
    grep -qE "^[[:space:]]*\"env -[i]\"," "$f" \
      && ! grep -vE "^[[:space:]]*--" "$f" | grep -qE "renamed\.id\(\"c0371\"\)|acceptance/c0371/|check-paths-homes|touched-from-home|uses-module"'

finish
