#!/usr/bin/env bash
# Acceptance checks for d0434. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/d0434 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/d0434"
SPEC="$A/restack-conflict.spec.luau"

# The spec's cases share one fixture, so it runs once (here, outside `check`: list mode refuses it); each check then
# requires its named case ("ACn:" starts the case's name) to exist in the spec and not fail. Any failing case that no
# criterion names (the set-up included), a failure count that the FAIL lines do not match, and a spec that did not
# load fail every criterion.
report_out=$(lune run tests/run -- "$SPEC" 2>&1)
named=$(grep -oE '^check "AC[0-9]+:' "$HERE/check.sh" | sed -E 's/^check "//')
whole_run() {
  local failed lines line c
  failed=$(sed -nE 's/^[0-9]+ passed, ([0-9]+) failed, 1 spec files$/\1/p' <<<"$report_out")
  lines=$(grep -cE "^FAIL .* :: " <<<"$report_out")
  [[ -n $failed && $failed == "$lines" ]] || { echo "the run counts ${failed:-no} failure(s) but names $lines:"; tail -20 <<<"$report_out"; return 1; }
  while IFS= read -r line; do
    c=${line#*:: }
    grep -qxF -- "${c%%:*}:" <<<"$named" || { echo "a case no criterion names failed: $c"; return 1; }
  done < <(grep -E "^FAIL .* :: " <<<"$report_out")
}
every_case_named() { # a case, passing or not, that no criterion names (set-up aside) fails every criterion
  local c
  while IFS= read -r c; do
    [[ $c == "sets up"* ]] && continue
    grep -qxF -- "${c%%:*}:" <<<"$named" || { echo "the spec's case \"$c\" is named by no criterion"; return 1; }
  done < <(tr -d "\n\t" <"$SPEC" | grep -oE 'it\("[^"]+"' | sed -E 's/^it\("//; s/"$//')
}
case_ok() { # $1: the case's "ACn:" prefix
  [[ -f $SPEC ]] || { echo "missing $SPEC"; return 1; }
  if grep -q "could not load spec" <<<"$report_out"; then echo "$report_out"; return 1; fi
  whole_run || return 1
  every_case_named || return 1
  tr -d "\n\t" <"$SPEC" | grep -qF "\"$1" || { echo "$SPEC has no case starting \"$1"; return 1; }
  if grep -E "^FAIL .* :: $1" <<<"$report_out"; then return 1; fi
}

check "AC1: a conflicted layer leaves its rebase in progress, exit 3, names layer, files and commands; layers below it that passed are pushed, it and the layers above are not; nothing is emitted" case_ok "AC1:"
check "AC2: a restack while one is in progress refuses, names both commands, and changes nothing (marker, stopped commit, staged content)" case_ok "AC2:"
check "AC3: work next names the resolve-and-continue action while a restack is stopped" case_ok "AC3:"
check "AC4: --continue refuses unmerged paths and staged conflict markers, naming them" case_ok "AC4:"
check "AC5: --continue finishes, restacks the layers above equal to a by-hand rebase, pushes each layer on its own as it passes and emits restacked once" case_ok "AC5:"
check "AC6: --abort restores every layer not yet pushed and the worktree, leaves the pushed layers as pushed, and never moves origin back" case_ok "AC6:"
check "AC7: a hand-rebased layer keeps its tip and the layer above is restacked on it; a red check.sh pushes nothing" case_ok "AC7:"
check "AC8: a restack whose rebase the worker continued by hand is finished by a plain restack" case_ok "AC8:"
check "AC9: a commit of someone else on origin's layer stops the restack, naming both tips, changing nothing" case_ok "AC9:"
check "AC10: a red check.sh stops the restack at its layer and pushes nothing for it or any layer above" case_ok "AC10:"
check "AC11: zz-execute and z-work tell the worker how to resolve, continue, recover and when to ask" case_ok "AC11:"
check "AC12: origin's layer re-finished with the same subject by someone else is refused" case_ok "AC12:"
check "AC13: a push to a layer between the stop and --continue is not overwritten: its lease fails and the run stops" case_ok "AC13:"
check "AC14: a rebase or resolution that empties a commit stops and asks, pushing nothing" case_ok "AC14:"
check "AC15: continue and abort with no rebase refuse a dirty worktree; a mid-walk stop is resumable and the layers that passed are pushed" case_ok "AC15:"
check "AC16: --abort refuses a branch that moved since the run left it" case_ok "AC16:"
check "AC17: a layer someone else fast-forwarded before the run is built on, and the first push succeeds with their commit" case_ok "AC17:"
check "AC18: a re-finish by someone else, fetched before the run, is not overwritten" case_ok "AC18:"
check "AC19: after an abort, a local amend does not overwrite a commit the first run had only fetched" case_ok "AC19:"
check "AC20: abort after a continue and a later red check puts every unpushed branch back and keeps the pushed one" case_ok "AC20:"
check "AC21: a diverged layer this clone did not push is refused, naming both tips and what to do" case_ok "AC21:"
check "AC22: a layer this clone pushed and then amended locally is trusted" case_ok "AC22:"
check "AC23: a push and a fetch between the stop and --continue: that layer's push fails its lease" case_ok "AC23:"
check "AC24: a marker with no conflict recorded and a rebase in progress is a stopped restack" case_ok "AC24:"
check "AC25: after an abort that left pushed layers, a plain restack picks up from them and finishes the stack" case_ok "AC25:"

finish
