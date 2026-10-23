#!/usr/bin/env bash
# Acceptance checks for c0057. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0057 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0057"
OLD="$PWD/tests/acceptance"

check "AC1: board opens the written page once, by its absolute path, by default" lune run tests/run -- "$A/open.spec.luau"
check "AC2: -O writes and prints the page but opens nothing, and takes no value" lune run tests/run -- "$A/open.spec.luau"
check "AC3: --open is still accepted; --open with -O is refused before writing" lune run tests/run -- "$A/open.spec.luau"
check "AC4: a failing opener only warns; the page is written and the exit code is 0" lune run tests/run -- "$A/open.spec.luau"
check "AC5: the usage text and the tracker skill's board row document -O" lune run tests/run -- "$A/open.spec.luau"
check "AC6: the board workflow builds with -O" lune run tests/run -- "$A/open.spec.luau"
check "AC7: the overridden board specs and the tooling board spec pass" lune run tests/run -- "$OLD/c0042/cli.spec.luau" "$OLD/c0048/board-workflow.spec.luau" "$OLD/c0048/board-docs.spec.luau" tests/tooling/board.spec.luau
check "AC8: tests/run fails a run in which a spec started a browser, and changes nothing else" lune run tests/run -- "$A/guard.spec.luau"
check "AC9: the testing skill's No browsers bullet names tests/run, -O and PICKMAN_OPEN_GUARD" bash -c 'l=$(grep -F -- "- **No browsers.**" .claude/skills/testing/SKILL.md) && grep -qF "tests/run" <<<"$l" && grep -qF -- "-O" <<<"$l" && grep -qF PICKMAN_OPEN_GUARD <<<"$l"'

finish
