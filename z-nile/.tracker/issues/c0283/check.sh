#!/usr/bin/env bash
# Acceptance checks for c0283. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0283 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0283"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.

check "AC1: the approved row is one parsed row, the old rows are kept, and every agent marker is read" \
  lune run tests/run -- "$A/approval.spec.luau"
check "AC2: ./zn approve is refused in an agent session even with a terminal, and --check still runs" \
  lune run tests/run -- "$A/approve.spec.luau"
check "AC3: ./zn approve commits approval.md and the approved row together by the git identity, appends on a second approval, and refuses a bad record first" \
  lune run tests/run -- "$A/approve.spec.luau"
check "AC4: the dispatcher's prep gate never merges, keeps its reasons and adds the approve suffix" \
  lune run tests/run -- "$A/dispatch.spec.luau"
check "AC5: zz-rules, z-design, the README, AGENTS.md and .models.toml state the refusal, the row and the prep gate" \
  lune run tests/run -- "$A/docs.spec.luau"
check "AC6: the real tree audits and lessons-checks clean and the overridden promoted specs pass in their narrowed form" \
  bash -c '"$ZN_ROOT/zn" audit && "$ZN_ROOT/zn" lessons --check && lune run tests/run -- tests/acceptance/c0117/dispatch.spec.luau tests/acceptance/c0117/control-cli.spec.luau tests/tooling/dispatch-guards.spec.luau tests/tooling/dispatch-texts.spec.luau tests/tooling/approve.spec.luau'

finish
