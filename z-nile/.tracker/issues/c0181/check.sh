#!/usr/bin/env bash
# Acceptance checks for c0181. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0181 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0181"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: a lesson file may carry enforced_by, enforced, not_codifiable, distinct_from and merged, and one without them parses as before" lune run tests/run -- "$A/format.spec.luau"
check "AC2: The policy requires a state on every lesson, caps the body by level, checks that each named check exists where the gate runs it (a lint that names the lesson, or a case named for it under a project's tests/), makes a near-duplicate pair merge or be marked distinct, refuses an unrewritten merge and a skill text naming a lesson that is gone; a harvest codify line is checked for shape and its lesson, and compared with the lesson only for the item named" lune run tests/run -- "$A/policy.spec.luau"
check "AC3: a fully enforced lesson is one line and hidden from --when and the prompt index, a partly enforced one stays with its question, --enforced and --codified report" lune run tests/run -- "$A/listing.spec.luau"
check "AC4: A lint is a pure scan over a scope that names its lesson, honours lint-ok marks and a baseline (by path or by item), proves itself on bad and good fixtures, reads only the work tree's own files, prints the lesson's body once, and fails closed on an empty scope" lune run tests/run -- "$A/lints.spec.luau"
check "AC5: the gate runs the policy and the lints as static stages on every run, and the registered lints and the lessons naming them are the same set" lune run tests/run -- "$A/wiring.spec.luau"
check "AC6: A failing spec case named by a lesson's enforced_by prints that lesson under it, and any other failure prints as before" lune run tests/run -- "$A/footer.spec.luau"
check "AC7: Overlap is scored from two lessons' own text, hard pairs are same-skill at 0.35 or more, and --consolidate [<lesson id>] reports them as clusters, related lessons of other skills and bodies over their cap" lune run tests/run -- "$A/consolidate.spec.luau"
check "AC8: lesson-merge folds lessons of one skill into one, rewrites every harvest.md and id, loses no source, refuses what it should and changes nothing when it does" lune run tests/run -- "$A/merge.spec.luau"
check "AC9: the skills and AGENTS.md state the codify-and-consolidate process once and point at it, in one order" lune run tests/run -- "$A/docs.spec.luau"
check "AC12: A rule is a pure check the tool runs at the moment of the mistake, a presence rule judges only a document whose Rules and mutants table has a data row, it names its lesson, proves itself on a bad and a good view, is cleared per item by lint-allow.md, is registered and named by its module both ways, every command calls it for its hook, and the proof stamp round-trips and goes stale" lune run tests/run -- "$A/rules.spec.luau"

# AC10: the backfill on the real tree. A one-time check (a threshold on live data), so it lives here and is not promoted.
codified() { # codified <field>: the number before the field's words in `./zn lessons --codified`'s first line
  local out
  out=$("$ZN_ROOT/zn" lessons --codified) || { echo "lessons --codified failed: $out" >&2; return 1; }
  printf '%s\n' "$out" | K="$1" perl -ne 'if (/(\d+) \Q$ENV{K}\E[ ,)]/) { print $1; exit }'
}
backfill() {
  local none bytes plan frozen now id cls f missing=0 cand merged strict m ok
  none=$(codified "without state") || return 1
  [[ -n $none ]] || { echo "could not read the --codified report"; return 1; }
  [[ $none -eq 0 ]] || { echo "$none lessons have no state"; return 1; }
  # the user's decision (2026-11-01): every lesson that can be converted to code is. A lesson that is not enforced and
  # does not say what was tried must be an N row of the plan (a reason the code review judges); a lesson absent from
  # the plan (one main added since) fails until a row for it is added to the plan, which lies in the item folder
  # the prep's classes are sequestered ($A/plan-classes.tsv); the editable plan (experiments/) classifies only lessons
  # main added since, and a row there that disagrees with the sequestered one fails
  frozen="$A/plan-classes.tsv"
  plan="$HERE/experiments/E2-classification.tsv"
  [[ -s $frozen && -s $plan ]] || { echo "no plan at $frozen or $plan"; return 1; }
  while IFS=$'\t' read -r id cls _; do
    now=$(awk -F'\t' -v id="$id" '$1 == id { print $2 }' "$plan")
    [[ -z $now || $now == "$cls" ]] || { echo "plan row changed: $id was $cls, is $now"; missing=$((missing + 1)); }
  done < "$frozen"
  # one loop over the lessons on disk. A lesson takes the strictest class (F > P > N) among its own id and every id in
  # its merged: line, since the sweep merges first and a merge must not launder a stricter class into a looser one.
  # Strictest F: enforced `full`, or a harvest.md line `- codify <its id or a merged id>: ... part: tried ...`.
  # Strictest F or P: enforced_by, or `not_codifiable: tried:`. Strictest N: nothing more (JC2 judges the reason).
  for f in "$ZN_ROOT"/z-nile/skills/*/lessons/*.md "$ZN_ROOT"/pickman/skills/*/lessons/*.md; do
    [[ -f $f ]] || continue
    cand=${f%/lessons/*}
    id="$(basename "$cand")/$(basename "$f" .md)"
    merged=$(sed -n 's/^merged: *//p' "$f")
    strict=
    for m in $id ${merged//,/ }; do
      cls=$(awk -F'\t' -v id="$m" '$1 == id { print $2 }' "$frozen")
      [[ -n $cls ]] || cls=$(awk -F'\t' -v id="$m" '$1 == id { print $2 }' "$plan")
      case $cls in
        F) strict=F ;;
        P) [[ $strict == F ]] || strict=P ;;
        N) [[ -n $strict ]] || strict=N ;;
      esac
    done
    [[ -n $strict ]] || { echo "$id is in no plan: add a row to experiments/E2-classification.tsv"; missing=$((missing + 1)); continue; }
    if [[ $strict == F ]] && ! grep -qE '^enforced: full$' "$f"; then
      ok=
      grep -qE '^not_codifiable: tried:' "$f" && ok=1
      for m in $id ${merged//,/ }; do
        grep -rqE --include=harvest.md "^- codify ${m}: .* part: (tried|decided) " "$ZN_ROOT"/z-nile/.tracker "$ZN_ROOT"/pickman/.tracker && ok=1
      done
      [[ -n $ok ]] || { echo "$id is F in the plan and neither enforced full nor recorded as part: tried or part: decided"; missing=$((missing + 1)); }
    fi
    if [[ $strict != N ]] && ! grep -qE '^(enforced_by:|not_codifiable: tried:)' "$f"; then
      echo "$id (plan class $strict) is neither enforced nor tried"; missing=$((missing + 1))
    fi
  done
  [[ $missing -eq 0 ]] || return 1
  # tight: the lesson files weigh at most 220000 bytes in all (243083 on 2026-11-01, before the sweep)
  # a byte sum that dies on a missing file (no pipe: a failing `cat | wc -c` would print the count of what it got)
  bytes=$(perl -e '$n = 0; for (@ARGV) { -f $_ or die "no file $_\n"; $n += -s _ } print $n' \
    "$ZN_ROOT"/z-nile/skills/*/lessons/*.md "$ZN_ROOT"/pickman/skills/*/lessons/*.md) || { echo "cannot sum the lessons"; return 1; }
  [[ $bytes -le 220000 ]] || { echo "lessons weigh $bytes bytes (limit 220000)"; return 1; }
  echo "bytes $bytes"
}
check "AC10: The policy and the lints pass on the repository and no hard pair is left" bash -c '
  set -e
  "$ZN_ROOT/zn" lessons --check --policy
  perl -e "alarm shift; exec @ARGV" 120 lune run "$ZN_ROOT"/z-nile/lints
  out=$("$ZN_ROOT/zn" lessons --consolidate) || { echo "lessons --consolidate failed"; exit 1; }
  if printf "%s\n" "$out" | grep -qF "must resolve"; then echo "a hard pair is left"; exit 1; fi
'
check "AC10b: Every lesson has a state, every lesson the plan calls F is enforced full or records the clause tried or decided, every lesson that is not enforced and does not say what was tried is an N row of the plan, and the lesson files weigh at most 220,000 bytes" backfill

# AC11: the existing lesson specs pass, and no promoted spec changes (Overrides: none)
no_lesson_lost() { # every lesson file the branch deletes was merged into a survivor that records it
  local gone id
  gone=$(git -C "$ZN_ROOT" diff --diff-filter=D --name-only origin/main...HEAD -- '*/skills/*/lessons/*.md') ||
    { echo "cannot compare with origin/main"; return 1; }
  for f in $gone; do
    id=$(printf '%s\n' "$f" | sed -n 's#.*/skills/\([^/]*\)/lessons/\(.*\)\.md#\1/\2#p')
    grep -qE "^merged:.*(^|[ ,:])$id([ ,]|$)" "$ZN_ROOT"/z-nile/skills/*/lessons/*.md "$ZN_ROOT"/pickman/skills/*/lessons/*.md ||
      { echo "lesson $id was deleted and no lesson lists it in merged:"; return 1; }
  done
}
check "AC10c: No lesson file is deleted unless a surviving lesson lists it in merged:" no_lesson_lost
check "AC11: The lesson specs that exist, the two that pin real lessons and the zz-arch table, the two guard scans, the two skill-text pins of the refusal sentence, the two that copy the runner and the two that plant a bad input for an older refusal pass unchanged" lune run tests/run -- tests/acceptance/c0111/lessons-cli.spec.luau tests/acceptance/c0111/lesson-format.spec.luau tests/acceptance/c0111/harvest.spec.luau tests/acceptance/c0111/select.spec.luau tests/acceptance/c0111/skill-docs.spec.luau tests/acceptance/c0111/prompt-lessons.spec.luau tests/acceptance/c0115/lessons.spec.luau tests/acceptance/c0119/scope-lessons.spec.luau tests/acceptance/c0172/merge.spec.luau tests/tooling/tracker-guarded.spec.luau tests/tooling/repo-fence.spec.luau tests/acceptance/c0077/cache-paths.spec.luau tests/acceptance/c0115/docs.spec.luau tests/acceptance/c0116/docs.spec.luau tests/tooling/run-record-merge.spec.luau tests/acceptance/c0114/gate-cover.spec.luau tests/acceptance/c0072/land.spec.luau tests/acceptance/c0045/workstreams.spec.luau
promoted_unchanged() {
  local out changed
  # git's own failure (no origin/main, a bad pathspec) is red, never filtered away
  out=$(git -C "$ZN_ROOT" diff --name-only origin/main...HEAD -- "$ZN_ROOT/pickman/tests/acceptance" "$ZN_ROOT/z-nile/tests/acceptance" 2>&1) ||
    { echo "cannot compare with origin/main: $out"; return 1; }
  changed=$(printf '%s\n' "$out" | awk '!/^z-nile\/tests\/acceptance\/c0181\// && NF')
  [[ -z $changed ]] || { echo "promoted specs changed: $changed"; return 1; }
}
check "AC11b: No promoted spec changes" promoted_unchanged
typecheck() { # the gate's Lune type stage over what this issue edits and what builds the types it changes
  # paths through "$ZN_ROOT": the check-paths scanners read a bare z-nile/... word, or a cd to a root, as a path from this item's home
  perl -e 'alarm shift; exec @ARGV' 300 luau-lsp analyze --base-luaurc="$ZN_ROOT/.luaurc" --platform=standard \
    --ignore='**/.tracker/**' --ignore='**/.cache/**' "$ZN_ROOT"/z-nile/engine "$ZN_ROOT"/z-nile/lints \
    "$ZN_ROOT"/z-nile/tests/acceptance/c0111 "$ZN_ROOT"/z-nile/tests/acceptance/c0119
}
check "AC11c: The promoted lesson specs and the new modules type-check as the gate checks them (a new required field breaks a hand-built Lesson or Item)" typecheck

finish
