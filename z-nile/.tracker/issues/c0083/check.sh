#!/usr/bin/env bash
# Acceptance checks for c0083. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0083 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0083"

check "AC1: suites.of, projects, changed and crossings name the harness suite (z-nile) and the game suite (every game project), a mixed change touches both, a tracker document none" lune run tests/run -- "$A/suites.spec.luau"
check "AC2: suites.of and watch.forSuite agree for every registered project" lune run tests/run -- "$A/suites.spec.luau"
check "AC3: affected --suite prints one suite's project names, changed names the suites the paths touch, a bad value exits 2" lune run tests/run -- "$A/gate.spec.luau"
check "AC4: check.sh --suite runs one suite's projects alone (--full --suite changed is every spec of each touched suite, a bare --full every project), and refuses a bad value or --project beside it before any tool runs" lune run tests/run -- "$A/gate.spec.luau"
check "AC5: a watch file that names the other suite's path fails watch-check, and the real tree has none" lune run tests/run -- "$A/suites.spec.luau" "$A/gate.spec.luau"
check "AC6: on the real tree a game change selects no tooling spec and a tooling change no game spec" lune run tests/run -- "$A/gate.spec.luau"
check "AC7: zz-test names the suites, --suite, the watch-check rule and when both suites run" lune run tests/run -- "$A/docs.spec.luau"
# no promoted spec of any home changes: Overrides: none (c0083's own folder is the only addition)
promoted_unchanged() {
  local out changed
  out=$(git -C "$ZN_ROOT" diff --name-only origin/main...HEAD 2>&1) ||
    { echo "cannot compare with origin/main: $out"; return 1; }
  changed=$(printf '%s\n' "$out" | grep -E '^[^/]+/tests/acceptance/' | grep -Ev '^z-nile/tests/acceptance/c0083/' || true)
  [[ -z $changed ]] || { echo "promoted specs changed: $changed"; return 1; }
}
check "AC8: no promoted spec changes (Overrides: none)" bash -c "$(declare -f promoted_unchanged); ZN_ROOT='$ZN_ROOT'; promoted_unchanged"
check "AC9: promotion routes an item's acceptance specs by its project, never by its type" lune run tests/run -- "$A/suites.spec.luau"
check "AC10: Merging still runs a game pull request's clean-clone bare --full" lune run tests/run -- "$A/docs.spec.luau"

finish
