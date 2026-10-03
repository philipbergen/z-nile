#!/usr/bin/env bash
# Acceptance checks for c0790. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0790 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0790"

# each spec runs once; a check requires its named cases to exist and the whole spec to pass
out_stats=$(lune run tests/run -- "$A/stats.spec.luau" 2>&1)
out_history=$(lune run tests/run -- "$A/history.spec.luau" 2>&1)
out_board=$(lune run tests/run -- "$A/board-stats.spec.luau" 2>&1)
cases_pass() { # $1: stats | history | board-stats; then case-name prefixes (bash 3.2: no associative arrays)
  local s=$1 out c; shift
  case $s in stats) out=$out_stats ;; history) out=$out_history ;; *) out=$out_board ;; esac
  if grep -q "could not load spec" <<<"$out"; then echo "$out"; return 1; fi
  grep -Eq "^[0-9]+ passed, 0 failed, 1 spec files$" <<<"$out" || { echo "$out" | tail -n 40; return 1; }
  for c in "$@"; do
    # stylua may wrap `it(` and a long name over two lines: join lines before matching
    tr -d '\n\t' < "$A/$s.spec.luau" | grep -qF "it(\"$c" || { echo "$s has no case starting \"$c\""; return 1; }
  done
}

check "AC1: floor, views and periods round down to Monday, the 1st, the quarter start and Jan 1" cases_pass stats \
  "floor rounds a day down" "the month, quarter and year views" "the periods are calendar-aligned"
check "AC2: rows count opened, closed, net, minutes and lines per type, half-open" cases_pass stats \
  "a row counts opened" "compute assembles views"
check "AC3: defect and chore ratios by count and time, nil when empty" cases_pass stats "ratios are percentages"
check "AC4: time in state counts only closed spells, per type, mean and median" cases_pass stats "durations count only closed spells"
check "AC5: history.parse derives spells, close days and today from git log" cases_pass history \
  "parse turns status stamps into spells" "a legacy start's move to active" "today is the last commit's day"
check "AC6: the board carries stats, has a Stats section beside the tabs, and builds deterministically" cases_pass board-stats \
  "the model carries stats" "the page has the Stats button" "builds of one tree are identical" "the real tracker's board has history"
check "AC7: board.yml fetches full history, and the overridden c0460 case passes" bash -c '
  lune run tests/run -- '"$A"'/board-stats.spec.luau tests/acceptance/c0460/board-workflow.spec.luau'

finish
