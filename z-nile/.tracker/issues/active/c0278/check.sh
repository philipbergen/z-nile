#!/usr/bin/env bash
# Acceptance checks for c0278. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0278 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0278"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.

# The fixture specs publish to their own fixture's origin. Until d0298 lands, a spec run started inside a dispatched
# step inherits the step's publish broker and fails there ("Operation not permitted" at broker.request: E6, with
# c0116/claims as the control), so these specs run without the step's variables. d0298 owns that fix
# (lesson z-design/checks-pass-in-a-dispatched-step).
nostep() {
  local p="" d
  local IFS=:
  for d in $PATH; do [[ $d == */z-nile/bin ]] || p="${p:+$p:}$d"; done
  env -u ZN_PUBLISH_BROKER -u ZN_PUBLISH_TOKEN -u ZN_DISPATCH -u ZN_HEADLESS -u ZN_DISPATCH_DIR \
    -u ZN_DISPATCH_HOME -u ZN_DISPATCHER_PID -u ZN_MEASURE_FILE PATH="$p" "$@"
}

check "AC1: closing's rules: the reason, the refusals in their order, the edit, the readers, and no status move into or out of closed" lune run tests/run -- "$A/closing.spec.luau"
check "AC2: the publish guard accepts exactly a close and never publishes a closed document again" nostep lune run tests/run -- "$A/closing.spec.luau" "$A/readers.spec.luau"
check "AC3: ./zn close publishes one tracker-only commit that stamps status: closed-… and adds wont_do:, and the folder stays findable" nostep lune run tests/run -- "$A/close-cli.spec.luau"
check "AC4: close refuses each case, naming its way out, and publishes nothing" nostep lune run tests/run -- "$A/close-cli.spec.luau"
check "AC5: close --carry writes the same document in this tree, publishes nothing, and is judged on this tree" nostep lune run tests/run -- "$A/close-cli.spec.luau"
check "AC6: list, the bare status listing, the board and raft-plan leave a closed issue out; list closed and status <id> show it" nostep lune run tests/run -- "$A/readers.spec.luau"
check "AC7: status moves, status <id> closed, idea, fold and new raft refuse a closed issue" nostep lune run tests/run -- "$A/readers.spec.luau"
check "AC8: the dispatcher stops a closed issue as finished, and watch-net's open-defect test ignores it" nostep lune run tests/run -- "$A/readers.spec.luau"
check "AC9: audit reports the four closed-* codes with their fixes, and nothing for a proper close" nostep lune run tests/run -- "$A/readers.spec.luau"
check "AC10: zz-rules and the usage text document close and list closed; close is neither read-only nor allowed in the main checkout" lune run tests/run -- "$A/docs.spec.luau"

# c0268 is closed on this branch by ./zn close --carry (Design section 8): a closed-… status, its wont_do: reason,
# and no closed-* problem from the audit. Read from this tree, wherever c0268's folder is.
closed_here() {
  local id=$1 dir doc st why
  dir=$("$ZN_ROOT/zn" find "$id") || { echo "no $id"; return 1; }
  doc="$ZN_ROOT/$dir/$id.md"
  [[ -f $doc ]] || doc="$PWD/$dir/$id.md"
  st=$(awk '/^---$/{n++; next} n==1 && /^status: /{print $2; exit}' "$doc")
  why=$(awk '/^---$/{n++; next} n==1 && /^wont_do: /{sub(/^wont_do: /, ""); print; exit}' "$doc")
  [[ $st =~ ^closed-[a-z]+-[a-z]+-[a-z]+$ ]] || { echo "$id's status is $st, not closed-…"; return 1; }
  [[ -n ${why// /} ]] || { echo "$id has no wont_do: reason"; return 1; }
  if "$ZN_ROOT/zn" audit 2>&1 | grep -E "closed-[a-z-]+ " | grep -F "$id"; then
    echo "audit reports $id"; return 1
  fi
  # carried, not published: a published close leaves its subject in the document's history for good
  if git log --format=%s HEAD -- "$doc" | grep -qxF "tracker: close $id won't do"; then
    echo "$id was closed by a published close, not carried in this branch"; return 1
  fi
  # no live item on origin/main (which done fetches before it runs this) depends on it: a backlog or active
  # item document, not itself closed, whose depends_on line names the id
  local p
  while IFS= read -r p; do
    [[ $p =~ /(issues|rafts)/(active/)?([cfdR][0-9]{4})/([cfdR][0-9]{4})\.md$ ]] || continue
    [[ ${BASH_REMATCH[3]} == "${BASH_REMATCH[4]}" ]] || continue
    git show "origin/main:$p" | awk '/^---$/{n++; next} n==1 && /^status: closed-/{c=1} END{exit !c}' && continue
    echo "origin/main's $p names $id in its depends_on"; return 1
  done < <(git grep --full-name -l -w -e "$id" --and -e '^depends_on:' origin/main -- ':(top,glob)*/.tracker/**' | sed 's#^origin/main:##')
}
check "AC11: c0268 is closed on this branch with its wont_do: reason by the carried close, audit reports nothing for it, and no live item on origin/main depends on it" bash -c "$(declare -f closed_here); ZN_ROOT='$ZN_ROOT'; closed_here c0268"

# AC12 runs four slow-tier specs (c0053/publish 13.2 s, c0067/publish-move 10.9 s, tooling/board 8.0 s, c0082/cli 5.6 s:
# 37.7 s): they pin the publish guard, list and the board, which this chore changes (lesson
# zz-test/check-sh-never-runs-the-slow-tier, its c0302 note). The other slow specs at risk run once, in step 11.
check "AC12: the promoted specs next to this chore still pass" nostep lune run tests/run -- tests/acceptance/c0053/publish.spec.luau tests/acceptance/c0081/publish-guard.spec.luau tests/acceptance/c0067/publish-move.spec.luau tests/acceptance/c0082/audit.spec.luau tests/acceptance/c0082/cli.spec.luau tests/acceptance/c0118/view.spec.luau tests/acceptance/c0081/skill-doc.spec.luau tests/tooling/status-fresh.spec.luau tests/tooling/watch.spec.luau tests/tooling/board.spec.luau

check "AC13: ./zn land refuses a capture that edits a closed issue's document or adds a closed issue to a depends_on, and zz-rules says so" nostep lune run tests/run -- "$A/close-cli.spec.luau" "$A/docs.spec.luau"

# c0224 (arcade's root) is closed on this branch the same way (Design section 8, the Scope decision of 2026-11-15).
check "AC14: c0224 is closed on this branch with its wont_do: reason by the carried close, audit reports nothing for it, and no live item on origin/main depends on it" bash -c "$(declare -f closed_here); ZN_ROOT='$ZN_ROOT'; closed_here c0224"

finish
