#!/usr/bin/env bash
# Acceptance checks for c0267. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0267 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0267"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.

# A person's terminal for the specs that drive `./zn dispatch` and `./zn approve` in a fixture: every ZN_ variable of
# a dispatched step unset and z-nile/bin off PATH. Inside a dispatched step the runner's git fence otherwise resolves
# the step's wrapper as the real git (tests/tooling/approve.spec.luau is red there on main for the same reason) until
# d0298's runner drops the step's environment for every spec. Outside a step it changes nothing.
nostep() {
  local args=() v
  for v in $(compgen -e); do
    case $v in ZN_*) args+=(-u "$v") ;; esac
  done
  env "${args[@]}" PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v '/z-nile/bin$' | paste -sd: -)" "$@"
}

check "AC1: a prepared backlog raft with an unapproved issue stops the chain for the person (exit 3, not a failure), naming each issue, why, and one whole command line per issue that approves it" \
  lune run tests/run -- "$A/chain.spec.luau"
check "AC2: every approval matching (or none read) readies the raft; approvals that cannot be read stop as a failure naming why" \
  lune run tests/run -- "$A/chain.spec.luau"
check "AC3: the chain designs, merges the prep and rafts without waiting for an approval, and an active raft is not stopped" \
  lune run tests/run -- "$A/chain.spec.luau"
check "AC4: questions.md, an open list, a failed or tripped step and a done item still stop first" \
  lune run tests/run -- "$A/chain.spec.luau"
check "AC5: readycheck.waiting names the missing, unreadable and changed approvals in layer order, and nothing when ready refuses for anything else" \
  lune run tests/run -- "$A/waiting.spec.luau"
check "AC6: approval.stateOf is the one reading of an approval, and reasonOf's answers keep their heads with no one-time step" \
  lune run tests/run -- "$A/waiting.spec.luau"
check "AC7: ./zn dispatch stops before z-ready with nothing readied and no CLI started, and the printed line, run as printed, gets it through and leaves nothing" \
  nostep lune run tests/run -- "$A/wiring.spec.luau"
check "AC8: a changed contract stops it again, an unreadable approval's own line gets it through, two issues come in layer order, and a raft ready refuses for anything else still goes to z-ready" \
  nostep lune run tests/run -- "$A/wiring.spec.luau"
check "AC9: the README's picture and dispatcher line, zz-rules' chain rule and ready row, z-design's step 5 and z-ready say the design is a draft a person approves, and where the chain waits" \
  lune run tests/run -- "$A/docs.spec.luau"
check "AC10: the specs that pin the chain, the worker, ready and approve stay green" \
  nostep lune run tests/run -- tests/acceptance/c0117/dispatch.spec.luau tests/tooling/work.spec.luau \
  tests/tooling/readycheck.spec.luau tests/acceptance/c0117/docs.spec.luau tests/acceptance/c0115/readme.spec.luau \
  tests/acceptance/c0259/readme.spec.luau tests/acceptance/c0264/intent.spec.luau tests/tooling/dispatch-texts.spec.luau \
  tests/tooling/approve.spec.luau tests/tooling/approve-publish.spec.luau tests/tooling/ready-members.spec.luau
check "AC11: the dispatcher reads approvals only for a prepared backlog raft, and a read that fails, errors or answers nothing is unreadable, never an empty list" \
  lune run tests/run -- "$A/actsite.spec.luau"

finish
