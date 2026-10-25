#!/usr/bin/env bash
# Exit criteria for R0021. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: repo gate passes (full)" ./check.sh --full
# every issue naming this raft, including emergent ones
members=$(../zn members R0021) || members=""
check "RC0: the raft has member issues" test -n "$members"
for dir in $members; do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" ../zn promote-check R0021

# The incident's trigger, end to end: two suites of the git-heaviest fixture specs at once in this checkout.
# Both pass, the second waits for the first, and the repository is unchanged afterwards (config, branch, HEAD,
# worktrees under .cache, and refs whose tip a fixture identity wrote).
rc1() {
  local specs=(tests/acceptance/c0038/deferred.spec.luau tests/acceptance/c0008/done-order.spec.luau tests/acceptance/c0001/tracker-lifecycle.spec.luau)
  local snap='git config --local --get-regexp "^(remote|core|user)\." | grep -v "\.gh-resolved "; git symbolic-ref -q HEAD; git rev-parse HEAD; git worktree list --porcelain | grep "^worktree .*/\.cache/" | sort; git for-each-ref --format="%(refname) %(authoremail)" | grep "@example\.invalid>" | sort'
  local before after a b pid waited=0
  before=$(bash -c "$snap")
  a=$(mktemp); b=$(mktemp)
  lune run tests/run -- "${specs[@]}" >"$a" 2>&1 & pid=$!
  # start the second once the first holds the lock (a rendezvous, not a fixed sleep)
  while [[ ! -d .cache/tests-run.lock && $waited -lt 200 ]]; do sleep 0.05; waited=$((waited + 1)); done
  lune run tests/run -- "${specs[@]}" >"$b" 2>&1; local rb=$?
  wait "$pid"; local ra=$?
  after=$(bash -c "$snap")
  echo "first:";  tail -2 "$a"; echo "second:"; head -1 "$b"; tail -2 "$b"
  local ok=0
  [[ $ra -eq 0 && $rb -eq 0 ]] || { echo "a suite failed ($ra, $rb)"; ok=1; }
  grep -q "waiting for another test run" "$b" || { echo "the second suite did not wait"; ok=1; }
  [[ $before == "$after" ]] || { echo "the repository changed:"; diff <(echo "$before") <(echo "$after"); ok=1; }
  rm -f "$a" "$b"
  return $ok
}
check "RC1: two suites at once in one checkout both pass, the second waits, and the repository is unchanged" rc1

finish
