#!/usr/bin/env bash
# Acceptance checks for c0680. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0680 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0680"

# the 23 case names of tests/acceptance/c0510/commands.spec.luau, frozen in prep (2026-10-03)
NAMES=(
  "sets up a bare origin, a main checkout and a second terminal"
  "new issue publishes the stub to origin/main and syncs the worktree to it"
  "a local edit of the stub merges with origin/main without an add/add conflict"
  "ids are allocated above the highest id on origin, not only in the local tree"
  "an id taken by another terminal during the push is never overwritten: the next one is used"
  "new raft claims its members in one commit, or none of them"
  "status lists what origin says, even when this checkout is stale"
  "a status move refuses to run in the main checkout, which is never edited"
  "a move to prepared is carried by the PR: local edit only, nothing published"
  "a move is checked against origin, not the local file; invalid moves change nothing"
  "a prepared raft starts once: the second terminal is refused and nothing moves"
  "sync brings a worktree and the main checkout up to date"
  "a published move abandons prep for a raft and its members in one commit"
  "a raft move follows the local member list: unclaimed members refuse, dropped members are untouched"
  "new issue refuses --raft for a backlog raft, and new raft refuses an unclean tree"
  "an existing draft raft is claimed with status preparing, once; an issue in a raft is not stolen"
  "a tracker command in a directory that lost its .git refuses instead of using the enclosing repository"
  "a started raft goes back to prepared on origin, and the branch that already moved it merges cleanly"
  "a start that dies after its claim is resumed by this terminal and refused to every other"
  "sync --fetch updates origin/main and leaves HEAD alone; new issue in a raft worktree does not merge"
  "PICKMAN_PUBLISH=0 keeps a command local: ids step by 10 and nothing is pushed"
  "raft ids come from the union of the local tree and origin, and an item made ready offline can start"
  "stamps from processes started together differ, so identical moves conflict in git"
)
cases_kept() {
  local f=tests/acceptance/c0510
  [[ ! -e $f/commands.spec.luau ]] || { echo "$f/commands.spec.luau still exists"; return 1; }
  local joined n c
  joined=$(cat "$f"/commands-*.spec.luau 2>/dev/null | tr -d '\n\t')
  for n in "${NAMES[@]}"; do
    c=$(grep -oF "it(\"$n\"" <<<"$joined" | wc -l | tr -d ' ')
    [[ $c == 1 ]] || { echo "case found $c times: $n"; return 1; }
  done
}
own_fixtures() {
  local f files names
  files=(tests/acceptance/c0510/commands-*.spec.luau)
  [[ ${#files[@]} -ge 4 && -e ${files[0]} ]] || { echo "fewer than 4 part files"; return 1; }
  names=$(for f in "${files[@]}"; do grep -o 'trackerfix\.new("c0510-commands-[a-z0-9-]*"' "$f" || { echo "MISSING:$f"; }; done)
  grep -q MISSING <<<"$names" && { echo "$names" | grep MISSING; return 1; }
  [[ $(sort <<<"$names" | uniq -d) == "" ]] || { echo "two parts share a fixture"; return 1; }
  [[ $(wc -l <<<"$names" | tr -d ' ') == "${#files[@]}" ]] || { echo "a part creates more or fewer than one fixture"; return 1; }
}
parts_pass() { lune run tests/run -- tests/acceptance/c0510/commands-*.spec.luau; }
lib_types() {
  [[ -f tests/lib/trackerfix.luau ]] || { echo "no tests/lib/trackerfix.luau"; return 1; }
  luau-lsp analyze --base-luaurc=.luaurc tests/lib/trackerfix.luau 2>&1 | grep -v "^\[" | grep -E "Error" && return 1
  return 0
}

check "AC1: all 23 cases survive the split exactly once; the single file is gone" cases_kept
check "AC2: at least four parts, each with its own fixture" own_fixtures
check "AC3: the parts pass together" parts_pass
check "AC4: the shared fixture library type-checks" lib_types

finish
