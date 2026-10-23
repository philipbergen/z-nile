#!/usr/bin/env bash
# Acceptance checks for c0084. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0084 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0084"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
spec_ok() { # $1: spec file; the rest: case-name prefixes that must exist in it. The whole spec must pass.
  local name=$1 spec="$A/$1" out c
  shift
  out=$(lune run tests/run -- "$spec" 2>&1)
  if grep -q "could not load spec" <<<"$out"; then echo "$out" | tail -n 20; return 1; fi
  grep -Eq "^[0-9]+ passed, 0 failed, 1 spec files$" <<<"$out" || { echo "$out" | tail -n 40; return 1; }
  for c in "$@"; do
    # stylua may wrap `it(` and a long name over two lines: join lines before matching
    tr -d '\n\t' <"$spec" | grep -qF "it(\"$c" || { echo "$name has no case starting \"$c\""; return 1; }
  done
}

check "AC1: the ledger reads every spend.md shape and writes nine-column rows that never break" spec_ok ledger.spec.luau \
  "reads seven-cell rows as build" "reads c0073's fixture shape" "refuses malformed rows" "renders nine cells per row" \
  "never lets a cell break the table" "appends a numbered row"
check "AC2: ./zn spend publishes appended rows, counts only prep's own lines, and refuses what it must" \
  spec_ok spend-command.spec.luau "publishes one capture row" "splits a raft's row" "prep counts the lines" \
  "prep lines are the prep branch's own" "refuses bad input" "refuses an item that is active" "records deliver on a done item" \
  "keeps an existing ledger's rows"
check "AC3: commit records --phase and --tokens, done records deliver, the raft summary shows phases" \
  spec_ok commit-phase.spec.luau "records build by default" "records the phase and tokens" "splits tokens over the issues" \
  "refuses an unknown phase" "done records its own commit as deliver"
appended_only() {
  spec_ok ledger.spec.luau "accepts only appended rows" &&
    spec_ok spend-command.spec.luau "the publisher takes only appended rows" "status lists each item once" \
      "ready and stop carry the members' ledgers unchanged"
}
check "AC4: the publisher takes only appended rows to an issue's spend.md; ready and stop move ledgers unchanged; status lists each item once" appended_only
check "AC5: metrics prints spend by phase, per raft, design-review cost per round, and the rework scope" \
  spec_ok metrics-phases.spec.luau "lists every counted issue with its tokens" "sums agent-minutes by phase" \
  "gives each raft with counted issues" "prices a design round" "keeps the review-rounds table" "counts every phase in rework"

skills_record_every_phase() {
  local S=.claude/skills
  # sec <file> <line that starts the section> <line that starts the next one, empty: to the end>
  sec() { awk -v s="$2" -v e="$3" 'index($0, s) == 1 {p=1} p && e != "" && index($0, e) == 1 && index($0, s) != 1 {p=0} p' "$1"; }
  grep -E "^6\. " "$S/make-issue/SKILL.md" | grep -qF -- "./zn spend <id> --phase capture" ||
    { echo "make-issue step 6 does not record the capture"; return 1; }
  sec "$S/ticket-prep/SKILL.md" "## 5." "## 6." |
    grep -qF -- "--phase design-review --time <reviewer minutes> --tokens <reviewer tokens> --note design-review-NNN" ||
    { echo "ticket-prep 5 does not record each round's reviewer run"; return 1; }
  sec "$S/ticket-prep/SKILL.md" "## 5." "## 6." | grep -qF -- "--note design-refute-NNN" ||
    { echo "ticket-prep 5 does not record the answering time"; return 1; }
  sec "$S/ticket-prep/SKILL.md" "## 6." "" | grep -qF -- "--phase prep" || { echo "ticket-prep 6 does not record prep"; return 1; }
  sec "$S/execute-raft/SKILL.md" "## Phase 4" "## Phase 5" | grep -qF -- "--phase code-review --time <reviewer minutes> --tokens <reviewer tokens>" ||
    { echo "execute-raft Phase 4 does not record code review with the reviewer's minutes and tokens"; return 1; }
  sec "$S/execute-raft/SKILL.md" "## Phase 6" "## Stop" | grep -Eq -- 'zn spend R[0-9]+ --phase deliver' ||
    { echo "execute-raft Phase 6 does not record delivery after the merge"; return 1; }
  if grep -rnF -- "--time 0" "$S"; then echo "a skill still records with --time 0"; return 1; fi
  local t="$S/tracker/SKILL.md" p
  grep -qE '^\| spend \|' "$t" || { echo "tracker skill: no spend row in the command table"; return 1; }
  for p in capture prep design-review build code-review deliver; do
    sec "$t" "## Spend" "## " | grep -qF "\`$p\`" || { echo "tracker skill: ## Spend does not name $p"; return 1; }
  done
  grep -F "**The direct-push exception.**" "$t" | grep -qF "spend.md" || { echo "tracker skill: the direct-push exception does not name spend.md"; return 1; }
  sec "$t" "## Other commands" "## Sync" | grep -qF "./zn spend" || { echo "tracker skill: Other commands lacks spend"; return 1; }
  grep -qiF "by phase" "$S/metrics/SKILL.md" && grep -qiF "per round" "$S/metrics/SKILL.md" ||
    { echo "metrics skill does not explain the phase tables"; return 1; }
}
check "AC6: the skills record every phase, and none keeps --time 0" skills_record_every_phase

one_ledger_format() {
  local f code bad=0
  [[ -f z-nile/engine/ledger.luau ]] || { echo "z-nile/engine/ledger.luau is missing"; return 1; }
  for f in z-nile/engine/*.luau; do
    [[ $f == z-nile/engine/ledger.luau ]] && continue
    code=$(grep -vE '^[[:space:]]*--' "$f") # comment lines don't count (store.luau's layout comment names spend.md)
    # the row format is spelled in the ledger alone
    if grep -nF "| when | commit |" <<<"$code"; then echo "$f spells the spend row format itself"; bad=1; fi
    # a module whose code names spend.md reads or writes it through the ledger's functions
    if grep -qF "spend.md" <<<"$code" && ! grep -qE 'ledger\.(parse|append|render|appendOnly|sum|byPhase)\(' <<<"$code"; then
      echo "$f names spend.md in code but calls no ledger function"; bad=1
    fi
  done
  for f in spend publish; do
    grep -qE 'ledger\.(parse|append|render|appendOnly)\(' "z-nile/engine/$f.luau" || { echo "$f.luau does not use the ledger"; bad=1; }
  done
  return $bad
}
check "AC7: spend.md is read and written only through z-nile/engine/ledger.luau" one_ledger_format

finish
