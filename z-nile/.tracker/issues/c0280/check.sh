#!/usr/bin/env bash
# Acceptance checks for c0280. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0280 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0280"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: a Co-Authored-By trailer is an agent actor with a normalised model id, a value whose email is a commit author's is a person, a value with no email an agent, and a commit's actor is the last agent trailer, else its author" \
  lune run tests/run -- "$A/provenance-cases.spec.luau"
check "AC2: the trail log carries each commit's author, email, parents and Co-Authored-By values, provenance.md is no document, and trail.cut and trail.lifeOf give a life as read does" \
  lune run tests/run -- "$A/provenance-cases.spec.luau"
check "AC3: select derives the idea (a cut life's start marked), every change of the status word with its author, the unblock not covered by a record change, the rafter, the delivery by the arrival rule and the merge by the landing commit's agent trailer" \
  lune run tests/run -- "$A/provenance-cases.spec.luau"
check "AC4: merge orders entries oldest first (derived by commit time, derived before stored in one minute), lets a stored row win over the git fallback only for the same raft, and joins the worker read from the spend rows" \
  lune run tests/run -- "$A/provenance-cases.spec.luau"
check "AC5: ./zn who prints the history for a plain life, a reused number, a first-add idea, an old item, a done item, a cut life, a --no-ff landing and a raft, reads the published mainline only, writes nothing, works in the main checkout and refuses no history, a bad record and a bad spend.md naming the file" \
  lune run tests/run -- "$A/who.spec.luau"
check "AC6: the reader the board shares holds: select with no fronts derives the idea alone, trail.lifeOf builds read's life, and ./zn who prints through who.entries" \
  lune run tests/run -- "$A/provenance-cases.spec.luau" "$A/who.spec.luau"
check "AC7: zz-rules, the README and the usage text name ./zn who and what it derives" \
  lune run tests/run -- "$A/provenance-cases.spec.luau"
check "AC8: the real tree audits and lessons-checks clean and the promoted specs this layer touches stay green" \
  bash -c '"$ZN_ROOT/zn" audit && "$ZN_ROOT/zn" lessons --check && lune run tests/run -- tests/acceptance/c0119/capture-cli.spec.luau tests/acceptance/c0111/trail.spec.luau tests/acceptance/c0115/docs.spec.luau tests/acceptance/c0116/docs.spec.luau tests/acceptance/c0067/ready.spec.luau tests/acceptance/c0084/spend-command.spec.luau tests/tooling/tracker-review-guards.spec.luau'

finish
