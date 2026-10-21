#!/usr/bin/env bash
# Exit criteria for R0031. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: repo gate passes (full)" z-nile/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(./zn members R0031); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" ./zn promote-check R0031

# Done checks that read the skills or main.luau this raft edits (c0035 was edited in prep to accept --phase code-review).
# c0067-c0072 are R0025's, done before this raft starts; each is found wherever it is.
done_checks_hold() {
  local id d bad=0
  for id in c0005 c0008 c0035 c0067 c0068 c0069 c0070 c0071 c0072; do
    d=$(./zn find "$id") || { echo "$id not found"; bad=1; continue; }
    bash "$d/check.sh" >/dev/null 2>&1 || { echo "$id's check.sh fails"; bad=1; }
  done
  local m=.claude/skills/metrics/SKILL.md
  grep -q 'zn sync --fetch' "$m" || { echo "metrics skill lost its './zn sync --fetch' step"; bad=1; }
  if grep -Eq 'zn sync([^ -]|$)' "$m"; then echo "metrics skill runs the merging sync"; bad=1; fi
  return $bad
}
check "RC1: the done checks of c0005, c0008, c0035 and R0025's members, and c0053's metrics sync rule, still hold" done_checks_hold

check "RC2: no member acceptance spec names what the gate scan bans, or runs a shell string" bash -c '
  # the banned list is read from the scan itself, so this file names none of it
  f=tests/tooling/repo-fence.spec.luau
  [ -f "$f" ] || { echo "$f is missing"; exit 1; }
  names=$(sed -n "/^local NAMES = {/,/^}/p" "$f" | grep -o "\"[^\"]*\"" | tr -d "\"")
  [ -n "$names" ] || { echo "read no banned names from $f"; exit 1; }
  bad=""
  for d in $(./zn members R0031); do
    [ -d "$d/acceptance" ] || continue
    while IFS= read -r n; do
      hit=$(grep -rliF -- "$n" "$d/acceptance" || true)
      [ -z "$hit" ] || bad="$bad$hit names $n\n"
    done <<<"$names"
    hit=$(grep -rnE "\"(ba)?sh\", *\{ *\"-c\"|process\.create" "$d/acceptance" || true)
    [ -z "$hit" ] || bad="$bad$hit\n"
  done
  [ -z "$bad" ] || { printf "%b" "$bad"; exit 1; }'

narrowed_override() { # c0053's publish spec moves exactly one entry, an issue's spend.md, from the refused list to the allowed one
  local f=tests/acceptance/c0053/publish.spec.luau was now
  was=$(git show "$(git merge-base origin/main HEAD):$f") || { echo "cannot read $f at the merge base"; return 1; }
  now=$(cat "$f")
  # the spend.md line, wherever it sits, is the one line that may differ; the case name may say so too
  diff <(grep -vE 'spend\.md|^[[:space:]]*it\(|allows only an item' <<<"$was") <(grep -vE 'spend\.md|^[[:space:]]*it\(|allows only an item' <<<"$now") ||
    { echo "$f changed beyond the spend.md entry"; return 1; }
  [[ $(grep -cE '"tracker/issues/c[0-9]+/spend\.md"' <<<"$was") == 1 ]] || { echo "the base spec does not hold one spend.md entry"; return 1; }
  [[ $(grep -cE '"tracker/issues/c[0-9]+/spend\.md"' <<<"$now") == 1 ]] || { echo "the spec does not hold one spend.md entry"; return 1; }
  sed -n '/for _, ok in/,/do$/p' <<<"$now" | grep -qE '"tracker/issues/c[0-9]+/spend\.md"' ||
    { echo "the spend.md entry is not in the allowed list"; return 1; }
}
check "RC3: c0053's publish spec is narrowed by exactly the spend.md entry (the raft's override)" narrowed_override

finish
