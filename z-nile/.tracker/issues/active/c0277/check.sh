#!/usr/bin/env bash
# Acceptance checks for c0277. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0277 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0277"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the pure rules: a copy is named with the smallest free numeric suffix; a family is the name and its numbered copies and its current member the highest one not discarded; a worktree's base is the branch name it keeps; a copy is fresh until the limit; --item is accepted for the item's own branch only; a worktree's claims may be taken over only when each is lost or already over; the marker lists what was left and one reader parses it, a damaged marker still refuses; a discarded worktree is finished with when none of its items is a live claim and kept while it holds unrecovered work; a beat loop stops for a discarded worktree" lune run tests/run -- "$A/plan.spec.luau"
check "AC2: worktree --takeover refuses a live, parked, unreadable, claim-less or wrong-branch worktree and a copy its taker is starting in, and moves nothing; renames the old directory and its branch and marks it; the numbered copy continues the pushed branch with the PR head untouched; a plain lookup finds the copy and never gives the bare name back; by id the worktree is found by its claim; the next takeover is -2; a failure puts everything back" lune run tests/run -- "$A/discard.spec.luau"
check "AC3: the old worker's work is recovered: pushed commits are in the copy and listed, unpushed commits stay on the renamed branch with a cherry-pick command that works as written, uncommitted files stay byte for byte and are listed, a branch never pushed and a detached head with commits are covered, and the old marks are deleted" lune run tests/run -- "$A/recover.spec.luau"
check "AC4: every ./zn command in a discarded worktree but the read-only ones and reap refuses before anything beats, a damaged marker included; a running beat loop and the dispatcher's beats stop (the proof is pinned by hash, so a changed proof fails here)" bash -c 'if [[ -d "$0/acceptance" ]]; then [[ $(git hash-object "$0/proofs/discard.spec.luau") == 868cee5e1dac4f2e2b83200fb07f72fd4e8abcbe ]] || { echo "proofs/discard.spec.luau changed since it was pinned" >&2; exit 1; }; lune run tests/run -- "$0/acceptance/guard.spec.luau" "$0/proofs/discard.spec.luau"; else lune run tests/run -- "$1/guard.spec.luau"; fi' "$HERE" "$A"
check "AC5: a discarded worktree is kept until the work it was discarded for ends and then removed with its branch, unless it holds unrecovered work, which is kept and listed by reap; a done raft's numbered copies go with it" lune run tests/run -- "$A/sweep.spec.luau"
check "AC6: the usage text, zz-rules, the skills and the README name the discard" bash -c '
  set -e
  g() { grep -qF -e "$1" "$2" || { echo "missing in $2: $1" >&2; exit 1; }; }
  R="$ZN_ROOT/z-nile"
  "$ZN_ROOT/zn" 2>&1 | grep -qF -e "worktree <name> --takeover" || { echo "usage lacks worktree <name> --takeover" >&2; exit 1; }
  "$ZN_ROOT/zn" 2>&1 | grep -qF -e "worktree --takeover <id>" || { echo "usage lacks worktree --takeover <id>" >&2; exit 1; }
  for w in "Discarding and recovering" "-discarded-" ".cache/discarded" ".cache/fresh" "family"; do g "$w" "$R/skills/zz-rules/SKILL.md"; done
  # c0436 override: z-run was renamed z-code (#761)
  for s in z-design z-raft z-code z-stop; do g "--takeover" "$R/skills/$s/SKILL.md"; done
  g "a lost prep" "$R/skills/z-design/SKILL.md"; g "origin/prep-<slug>" "$R/skills/z-design/SKILL.md"; g "after every commit" "$R/skills/z-design/SKILL.md"
  g "./zn sync --fetch && git push" "$R/skills/z-design/SKILL.md"; g "you were discarded" "$R/skills/z-design/SKILL.md"; g "you were discarded" "$R/skills/z-code/SKILL.md"; g "picks up something new" "$R/skills/zz-execute/SKILL.md"
  g "a lost rafting claim" "$R/skills/z-raft/SKILL.md"
  g "a lost raft" "$R/skills/z-code/SKILL.md"; g "--adopt" "$R/skills/z-code/SKILL.md"
  g "numbered copy" "$R/skills/z-stop/SKILL.md"; g "discarded for this raft" "$R/skills/z-stop/SKILL.md"
  g "numbered copy" "$R/skills/zz-execute/SKILL.md"
  for w in "you were discarded" "./zn lost" "--adopt" "with no raft" "never run \`./zn worktree <R>\`"; do g "$w" "$R/skills/z-work/SKILL.md"; done
  g "does the same on its own" "$R/skills/z-code/SKILL.md"; g "returned" "$R/skills/z-stop/SKILL.md"; g "discards it as a worktree of a claim already over" "$R/skills/zz-rules/SKILL.md"
  grep -qE "^\| .* \| c0277 \| exists \|" "$R/README.md" || { echo "README roadmap has no c0277 exists row" >&2; exit 1; }
'

check "AC7: a raft stopped from the main checkout and readied again does not send the next session into its old worktree: the plain lookup, and the dispatcher through it, discards a member that remembers a claim main no longer shows and returns the numbered copy, where the new claim is adopted and beaten; the old worktree stays refused; a worktree whose claims are its own, and a lookup that cannot read origin/main, are returned as before (the proof is pinned by hash, so a changed proof fails here)" bash -c 'if [[ -d "$0/acceptance" ]]; then [[ $(git hash-object "$0/proofs/discard.spec.luau") == 868cee5e1dac4f2e2b83200fb07f72fd4e8abcbe ]] || { echo "proofs/discard.spec.luau changed since it was pinned" >&2; exit 1; }; lune run tests/run -- "$0/acceptance/reready.spec.luau" "$0/proofs/discard.spec.luau"; else lune run tests/run -- "$1/reready.spec.luau"; fi' "$HERE" "$A"

finish
