#!/usr/bin/env bash
# Acceptance checks for c0121. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home: the root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0121 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0121"
# c0118's promoted specs (they exist once c0118 is done, which this issue waits for): built from a variable, so the
# repository-wide check-paths scan does not read them as paths that exist today
P18="$PWD/tests/acceptance/c0118"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the guard refuses a foreign Host, OPTIONS, a foreign Origin, a missing token and a non-JSON or GET action; plan and gh parse" \
  lune run tests/run -- "$A/guard.spec.luau"
check "AC2: the in-process server on 127.0.0.1 refuses each attack before any stub runs, runs ./zn dispatch by argument array, opens the PR, caches gh, reads worktree spend, rebuilds on change, flags a stale engine, stops" \
  lune run tests/run -- "$A/server.spec.luau"
check "AC3: the served page polls with its token, loads each model, shows live, stale, unavailable and unanswered, and posts the three actions; the static page never fetches" \
  lune run tests/run -- "$A/page.spec.luau"
check "AC4: ./zn board --serve refuses a bad port, -O and --out, a linked worktree and a taken port, is guarded, and is in the usage" \
  lune run tests/run -- "$A/cli.spec.luau"
check "AC5: zz-rules and the README describe the served board" \
  lune run tests/run -- "$A/docs.spec.luau"
check "AC6: c0118's board, its page and docs (overridden where it said planned) and the read-only set stay" \
  lune run tests/run -- "$P18/view.spec.luau" "$P18/history.spec.luau" \
  "$P18/model.spec.luau" "$P18/page.spec.luau" "$P18/docs.spec.luau" \
  "$P18/real.spec.luau" tests/acceptance/c0042/smoke.spec.luau tests/acceptance/c0107/page.spec.luau \
  tests/tooling/board.spec.luau tests/tooling/tracker-guarded.spec.luau
finish
