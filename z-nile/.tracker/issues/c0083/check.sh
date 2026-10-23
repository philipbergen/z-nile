#!/usr/bin/env bash
# Acceptance checks for c0083. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0083 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0083"

# The spec runs once (here, outside `check`: list mode refuses it); a check then requires its named cases to exist in
# the spec and not fail, and the spec to have loaded.
suites_out=$(lune run tests/run -- "$A/suites.spec.luau" 2>&1)
cases_in() { # $1: spec file, $2: its output, $3...: case-name prefixes that must exist and not fail
  local spec=$1 out=$2 c; shift 2
  [[ -f $spec ]] || { echo "missing $spec"; return 1; }
  if grep -q "could not load spec" <<<"$out"; then echo "$out"; return 1; fi
  grep -Eq "^[0-9]+ passed, [0-9]+ failed, 1 spec files$" <<<"$out" || { echo "$out" | tail -20; return 1; }
  for c in "$@"; do
    tr -d "\n\t" < "$spec" | grep -qF "it(\"$c" || { echo "$spec has no case starting \"$c\""; return 1; }
    if grep -F "FAIL" <<<"$out" | grep -qF ":: $c"; then grep -F -A3 ":: $c" <<<"$out"; return 1; fi
  done
}
suites() { cases_in "$A/suites.spec.luau" "$suites_out" "$@"; }

check "AC1: each spec is in the harness suite, the game suite, or (tests/meta) both, and the two cover every spec" suites \
  "a spec's suite: meta both, tooling harness, game folders and feature specs game, chores by their requires" \
  "the two suites cover every spec, and share only tests/meta"
check "AC2: a harness change runs the whole harness suite; a game change its game specs; the project files the game suite" suites \
  "a harness change runs the whole harness suite and no game-only spec" \
  "a tests/lib file outside the allowlist stays graph plus text" \
  "a game change runs only game specs, and the ones that depend on it" \
  "a mixed change unions every path, and a shared path is still ALL" \
  "a tracker item's documents select only the specs that name them, plus the real-tree audit" \
  "default.project.json runs the whole game suite plus only the specs that name it" \
  "lobby.project.json runs the whole game suite plus only the specs that name it"
check "AC3: a change to what every spec runs on, the jail and the gate included, runs everything" suites \
  "a change to what every spec runs on runs everything"
check "AC4: a file a spec reads as text selects that spec; a spec change selects the specs that scan every spec" suites \
  "a file a spec reads as text selects that spec, and a spec change selects the specs that scan every spec" \
  "a deleted or renamed file still selects the specs that named it"
check "AC5: scripts/affected --suite and --deps, and check.sh --suite" suites \
  "the selector's command line prints a suite, and selects by suite instead of ALL" \
  "check.sh --suite runs one suite's specs, and refuses a bad name before any tool runs"
check "AC6: the Stop hook gates whenever the selector picks a spec, harness changes included" suites \
  "the Stop hook gates whenever the selector picks a spec, harness changes included"
ac7() {
  local s=.claude/skills/testing/SKILL.md p=.claude/skills/ticket-prep/SKILL.md fact affected override item tok
  for fact in "harness suite" "game suite" "--suite" "scripts/lib/suites.luau" "TRACKER_TREE_READERS"; do
    grep -qF -- "$fact" "$s" || { echo "the testing skill does not mention $fact"; return 1; }
  done
  if grep -qF "force one" "$s"; then echo "the testing skill still has the old full-run rule"; return 1; fi
  affected=$(awk '/\*\*Touched modules\*\*/,/\*\*Unknowns/' "$p")
  grep -qF -- "scripts/affected -- --deps" <<<"$affected" || { echo "ticket-prep's Affected specs step does not use --deps"; return 1; }
  if grep -qF "scripts/affected -- <paths>" <<<"$affected"; then echo "ticket-prep still pastes the plain selector"; return 1; fi
  override=$(awk '/\*\*Override check\*\*/,/- \*\*Test plan\*\*/' "$p")
  grep -qF -- "scripts/affected -- --deps" <<<"$override" || { echo "ticket-prep's Override check does not use --deps"; return 1; }
  grep -qF -- "carries no list" <<<"$override" || { echo "ticket-prep's Override check dropped carries no list"; return 1; }
  grep -qF -- "ALL" <<<"$override" || { echo "ticket-prep's Override check dropped ALL"; return 1; }
  if grep -qF '(any `scripts/` or config path)' "$p"; then echo "ticket-prep still says every scripts/ path prints ALL"; return 1; fi
  item=$(awk '/4\. \*\*Regressions\*\*/,/^5\. /' .claude/skills/review/SKILL.md)
  grep -qF -- "scripts/affected -- --deps" <<<"$item" || { echo "the review skill's item 4 does not use --deps"; return 1; }
  if grep -qF "scripts/affected -- <path>" <<<"$item"; then echo "review item 4 still pastes the plain selector"; return 1; fi
  for tok in "Overrides:" "scripts/affected" "grep -rlF" "carries no list" "tests/acceptance" "depends_on" "placeholder" "high" "ALL"; do
    grep -qF -- "$tok" <<<"$item" || { echo "review item 4 dropped $tok"; return 1; }
  done
  local tpl=tracker/templates/issue/doc.md row mode
  grep -qF -- "scripts/affected -- --deps" "$tpl" || { echo "the issue template does not use --deps"; return 1; }
  if grep -qF "scripts/affected -- <" "$tpl"; then echo "the issue template still pastes the plain selector"; return 1; fi
  row=$(grep -F '| `lune run scripts/affected' "$s" || true)
  [[ -n $row ]] || { echo "the testing skill has no scripts/affected commands row"; return 1; }
  for mode in --suite --deps --which; do
    grep -qF -- "$mode" <<<"$row" || { echo "the scripts/affected commands row does not list $mode"; return 1; }
  done
  grep -qF "scripts/lib/suites.luau" .claude/skills/architecture/SKILL.md || {
    echo "the architecture skill does not say a further place joins the GAME list in scripts/lib/suites.luau"; return 1
  }
  lune run tests/run -- tests/acceptance/c0047/override-check.spec.luau
}
check "AC7: the testing skill describes the suites without the old full-run rule; ticket-prep and the review skill use --deps" ac7

ac8() {
  local line full_lines phase0 miss merging sec4 item2 code phase3 phrase
  if grep -nF "check.sh --full" \
    .claude/skills/execute-raft/SKILL.md .claude/skills/review/SKILL.md \
    .claude/skills/tracker/SKILL.md .claude/skills/ticket-prep/SKILL.md \
    tracker/templates/raft/check.sh tracker/templates/prompt.md; then
    echo "a step still runs check.sh --full"
    return 1
  fi
  if grep -qF "after a local full gate" .claude/skills/tracker/SKILL.md AGENTS.md; then
    echo "tracker or AGENTS.md still says after a local full gate"; return 1
  fi
  if grep -qF "for a raft, the full gate" .claude/skills/tracker/SKILL.md; then
    echo "tracker still says for a raft, the full gate"; return 1
  fi
  full_lines=$(grep -F "check.sh --full" .claude/skills/testing/SKILL.md || true)
  [[ -n $full_lines ]] || { echo "the testing skill never says where --full remains"; return 1; }
  while IFS= read -r line; do
    grep -qF "on demand" <<<"$line" || { echo "the testing skill names --full outside on-demand use: $line"; return 1; }
    if grep -Eq "raft|RC0|exit criteria" <<<"$line"; then
      echo "the testing skill ties --full to the raft gate: $line"; return 1
    fi
  done <<<"$full_lines"
  phase0=$(sed -n '/^## Phase 0/,/^## Phase 1/p' .claude/skills/execute-raft/SKILL.md)
  grep -qF -- "check.sh --suite" <<<"$phase0" || { echo "Phase 0 does not run the touched suites as its baseline"; return 1; }
  grep -qF -- "--which" <<<"$phase0" || { echo "Phase 0 does not key the baseline on --which"; return 1; }
  miss=$(awk '
    /^- \*\*Graph miss\*\*/ { on=1 }
    on && !/^- \*\*Graph miss\*\*/ && /^- \*\*/ { exit }
    on { print }
  ' .claude/skills/testing/SKILL.md)
  [[ -n $miss ]] || { echo "the testing skill has no Graph-miss bullet"; return 1; }
  grep -qF "selector miss" <<<"$miss" || { echo "the Graph-miss rule does not describe a selector miss"; return 1; }
  grep -qF "PR's branch" <<<"$miss" || { echo "the Graph-miss rule does not say to fix it on the PR's branch"; return 1; }
  grep -qF "tracker.sh new issue c" <<<"$miss" || { echo "the Graph-miss rule does not file a chore"; return 1; }
  if grep -qF 'fails under `--full` but wasn'"'"'t selected' <<<"$miss"; then
    echo "the Graph-miss rule still names a local --full run"; return 1
  fi
  merging=$(sed -n '/^## Merging/,/^## /p' .claude/skills/tracker/SKILL.md)
  for phrase in "selector miss" "lune run scripts/affected" "lune run tests/run --" "review-fix" "git commit" "absent from" "tests/acceptance"; do
    grep -qF -- "$phrase" <<<"$merging" || { echo "Merging is missing: $phrase"; return 1; }
  done
  sec4=$(sed -n '/^## 4\. /,/^## 5\. /p' .claude/skills/ticket-prep/SKILL.md)
  grep -qF "scripts/check.sh --affected" <<<"$sec4" || { echo "ticket-prep section 4 does not say RC0 runs --affected"; return 1; }
  item2=$(awk '/^2\. \*\*Acceptance criteria\*\*/,/^3\. /' .claude/skills/review/SKILL.md)
  grep -qF "RC0" <<<"$item2" || { echo "design item 2 does not mention RC0"; return 1; }
  grep -qF "scripts/check.sh --affected" <<<"$item2" || { echo "design item 2 does not require RC0 to run --affected"; return 1; }
  code=$(awk '/^2\. \*\*Sequestration\*\*/,/^3\. /' .claude/skills/review/SKILL.md)
  grep -qF "c0080" <<<"$code" || { echo "code item 2 does not name the c0080 exception"; return 1; }
  grep -qF -- "--affected" <<<"$code" || { echo "code item 2 does not name the --affected exception"; return 1; }
  phase3=$(sed -n '/^## Phase 3/,/^## Phase 4/p' .claude/skills/execute-raft/SKILL.md)
  grep -qF "c0080" <<<"$phase3" || { echo "Phase 3 sequestration does not name the c0080 exception"; return 1; }
  grep -qF -- "--affected" <<<"$phase3" || { echo "Phase 3 sequestration does not name the --affected exception"; return 1; }
  if grep -qF "template-drift" <<<"$merging"; then
    echo "Merging excepts a template-drift RC0 line"; return 1
  fi
  if grep -qF "not BLOCKED" <<<"$merging"; then
    echo "Merging excepts an RC0 line from BLOCKED"; return 1
  fi
  grep -qF "not a selector-miss exception" <<<"$item2" || {
    echo "design item 2 does not keep a stale RC0 out of the selector-miss rule"; return 1
  }
  grep -qF "c0037" <<<"$code" || { echo "code item 2 does not name the c0037 exception"; return 1; }
  grep -qF "c0037" <<<"$phase3" || { echo "Phase 3 sequestration does not name the c0037 exception"; return 1; }
}
check "AC8: no skill or template step runs check.sh --full; Phase 0 runs the touched suites; a selector miss is fixed forward, with no template-drift exception; Phase 3 and code item 2 name c0080 and c0037" ac8

# c0072.md and R0025.md stay as history. Land's live default is scripts/tracker/main.luau.
# One-shot RC0 proof lives here, not in a promoted spec. A missing origin/main fails; this check does not fetch.
ac9() {
  local rc=0 f raw removed added nr na c8 c37 dg n old new base rc0_line
  if grep -qF 'scripts/check.sh --full' scripts/tracker/main.luau; then
    echo "land still defaults to scripts/check.sh --full"; rc=1
  fi
  grep -qF 'override or "scripts/check.sh --affected"' scripts/tracker/main.luau || { echo "land does not default to scripts/check.sh --affected"; rc=1; }
  if grep -qF '"--full"' scripts/tracker/main.luau; then
    echo 'done still passes "--full"'; rc=1
  fi
  grep -qF 'doneGate(process.env)' scripts/tracker/main.luau || { echo "done no longer decides through doneGate(process.env)"; rc=1; }
  if grep -qF 'PICKMAN_DONE_GATE' scripts/tracker/main.luau; then
    echo "main.luau names PICKMAN_DONE_GATE"; rc=1
  fi
  c8=$(scripts/tracker.sh find c0080)/check.sh
  if grep -qF 'scripts/check.sh --full' "$c8"; then echo "c0080 still greps Phase 4 for scripts/check.sh --full"; rc=1; fi
  grep -qF 'scripts/check.sh --affected' "$c8" || { echo "c0080 does not grep Phase 4 for --affected"; rc=1; }
  c37=$(scripts/tracker.sh find c0037)/check.sh
  if grep -qF 'check.sh --full' "$c37"; then echo "c0037 still greps Merging for check.sh --full"; rc=1; fi
  grep -qF 'check.sh --affected' "$c37" || { echo "c0037 does not grep Merging for check.sh --affected"; rc=1; }
  grep -qF 'gh pr merge' "$c37" || { echo "c0037 dropped gh pr merge"; rc=1; }
  grep -qF 'Never use `--admin`' "$c37" || { echo "c0037 dropped Never use --admin"; rc=1; }
  dg=tests/acceptance/c0074/done-gate.spec.luau
  if grep -qF 'args: --full' "$dg"; then echo "c0074 still pins args: --full"; rc=1; fi
  n=$(grep -cF 'args: --affected' "$dg" || true)
  [[ $n -eq 2 ]] || { echo "c0074 should pin args: --affected twice, found $n"; rc=1; }
  grep -qF 'full gate fails' "$dg" || { echo "c0074 dropped full gate fails"; rc=1; }
  grep -qF 'full gate is skipped' "$dg" || { echo "c0074 dropped full gate is skipped"; rc=1; }
  n=$(grep -cF 'toBe("full")' "$dg" || true)
  [[ $n -ge 4 ]] || { echo "c0074 dropped the full mode name ($n)"; rc=1; }
  old='-check "RC0: repo gate passes (full)" scripts/check.sh --full'
  new='+check "RC0: repo gate passes (the suites this raft touches)" scripts/check.sh --affected'
  rc0_line='check "RC0: repo gate passes (full)" scripts/check.sh --full'
  # Every +/- body line, blanks included. Drop diff, index, hunk, and --- / +++ headers (the space is part of the header).
  diff_bodies() {
    raw=$(git diff -U0 --no-color origin/main...HEAD -- "$1" | grep -Ev '^(diff |index |@@|--- |\+\+\+ )' || true)
    removed=$(printf '%s\n' "$raw" | grep -E '^-' || true)
    added=$(printf '%s\n' "$raw" | grep -E '^\+' || true)
    nr=$(printf '%s\n' "$removed" | grep -cE '^-' || true)
    na=$(printf '%s\n' "$added" | grep -cE '^\+' || true)
  }
  base=$(git rev-parse --verify -q origin/main || true)
  if [[ -z $base ]]; then
    echo "origin/main is missing; AC9 does not fetch"
    rc=1
  else
    while IFS= read -r f; do
      [[ -z $f ]] && continue
      diff_bodies "$f"
      if [[ $f == tracker/issues/done/c0080/check.sh ]]; then
        [[ $nr -eq 1 && $na -eq 1 ]] || { echo "$f changes more than the Phase 4 grep"; rc=1; continue; }
        grep -qF 'scripts/check.sh --full' <<<"$removed" || { echo "$f did not remove the --full grep"; rc=1; }
        grep -qF 'scripts/check.sh --affected' <<<"$added" || { echo "$f did not add the --affected grep"; rc=1; }
        continue
      fi
      if [[ $f == tracker/issues/done/c0037/check.sh ]]; then
        [[ $nr -eq 1 && $na -eq 1 ]] || { echo "$f changes more than the Merging grep"; rc=1; continue; }
        grep -qF "check.sh --full" <<<"$removed" || { echo "$f did not remove the check.sh --full grep"; rc=1; }
        grep -qF 'scripts/check.sh --full' <<<"$removed" && { echo "$f removed scripts/check.sh --full; the grep is check.sh --full"; rc=1; }
        grep -qF 'check.sh --affected' <<<"$added" || { echo "$f did not add the check.sh --affected grep"; rc=1; }
        continue
      fi
      echo "a done/ check.sh changed: $f"; rc=1
    done < <(git diff --name-only origin/main...HEAD -- tracker/issues/done tracker/rafts/done | grep '/check\.sh$' || true)
    while IFS= read -r f; do
      [[ -z $f ]] && continue
      diff_bodies "$f"
      [[ $nr -eq 1 && $na -eq 1 ]] || { echo "$f changes more than its RC0 line"; rc=1; continue; }
      printf '%s\n' "$removed" | grep -qxF -- "$old" || { echo "$f: removed line is not the RC0 full gate"; rc=1; }
      printf '%s\n' "$added" | grep -qxF -- "$new" || { echo "$f: added line is not the new RC0"; rc=1; }
    done < <(git diff --name-only origin/main...HEAD -- tracker/rafts | grep -E '/check\.sh$' | grep -v '/done/' || true)
  fi
  # Working tree, not the diff: a raft left unedited is in no origin/main...HEAD name list.
  # Runs when origin/main is missing. Not done/. Not a promoted spec and not the gate. Names are not hardcoded.
  while IFS= read -r f; do
    [[ -z $f ]] && continue
    if grep -qF -- "$rc0_line" "$f"; then
      echo "$f still has the old RC0 line"
      rc=1
    fi
  done < <(find tracker/rafts \( -path '*/done/*' -o -path '*/done' \) -prune -o -name check.sh -type f -print)
  return $rc
}
check "AC9: each not-done raft check.sh and the c0080 and c0037 greps change by exactly one body line each, against the origin/main already present; a not-done raft check.sh still on the old RC0 line fails even without that ref; and land, done and c0074 agree" ac9
finish
