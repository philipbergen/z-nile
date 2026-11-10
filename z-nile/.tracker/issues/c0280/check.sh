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
check "AC1: a Co-Authored-By trailer is an agent actor with a normalised model id, and a commit's actor is the last agent trailer whose email is no commit author's, else its author, both read from git" \
  lune run tests/run -- "$A/provenance-cases.spec.luau"
check "AC2: the trail log carries each commit's author, email and Co-Authored-By values, provenance.md is no document, and trail.cut is read's cut of a life" \
  lune run tests/run -- "$A/provenance-cases.spec.luau"
check "AC3: select derives the idea, the status changes, the unblocked give-backs not covered by a record change, the rafter, the delivery and the merge of an item's life, and no rafter without raftAt" \
  lune run tests/run -- "$A/provenance-cases.spec.luau"
check "AC4: merge orders derived and stored entries oldest first, lets a stored row win over the git fallback only for the same raft, and joins the worker read from the spend rows" \
  lune run tests/run -- "$A/provenance-cases.spec.luau"
check "AC5: ./zn who prints the derived entries and the record for a plain life, a reused number, a first-add idea with stored and derived give-backs, an old item and a done item, writes nothing, works in the main checkout and refuses a bad record naming the file" \
  lune run tests/run -- "$A/who.spec.luau"
check "AC6: the reader the board shares holds: select with an empty raftAt gives every derived entry but the rafter, trail.cut is read's cut, and ./zn who prints through who.entries" \
  lune run tests/run -- "$A/provenance-cases.spec.luau" "$A/who.spec.luau"
check "AC7: zz-rules, the README and the usage text name ./zn who and what it derives" \
  lune run tests/run -- "$A/provenance-cases.spec.luau"
check "AC8: the real tree audits and lessons-checks clean and the promoted specs this layer touches stay green" \
  bash -c '"$ZN_ROOT/zn" audit && "$ZN_ROOT/zn" lessons --check && lune run tests/run -- tests/acceptance/c0119/capture-cli.spec.luau tests/acceptance/c0111/trail.spec.luau tests/acceptance/c0115/docs.spec.luau tests/acceptance/c0116/docs.spec.luau tests/acceptance/c0114/classified.spec.luau tests/tooling/tracker-review-guards.spec.luau'

finish
