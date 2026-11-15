#!/usr/bin/env bash
# Acceptance checks for c0292. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
# The lesson and the skill sentence are text: these checks read them here, at `./zn check` and at `done`, and no
# promoted spec pins their words (the shape c0192 and c0272 use). Each runs from z-nile/ (the item's project home);
# every command only reads (stylua and selene run with --check and --quiet, on this item's own folder).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
L=skills/z-design/lessons/prep-specs-pass-format-and-lint.md
H="$HERE/harvest.md"
export L H
# has <file> <literal>...: every literal is in the file, else name the first missing one
has() {
  local f=$1 w
  shift
  [[ -f $f ]] || { echo "no $f"; return 1; }
  for w in "$@"; do grep -qF -- "$w" "$f" || { echo "$f does not say: $w"; return 1; }; done
}
export -f has

check "AC1: the lesson z-design/prep-specs-pass-format-and-lint is read in design, tagged stylua, selene, format and lint, keeps the captured check question word for word, and is short (at most 14 lines, a body of at most 1,200 bytes)" \
  bash -c '[[ -f $L ]] || { echo "no $L"; exit 1; }
    n=$(( $(wc -l < "$L") )); [[ $n -le 14 ]] || { echo "$L has $n lines, at most 14"; exit 1; }
    b=$(( $(sed -e "1,/^---\$/d" "$L" | wc -c) )); [[ $b -le 1200 ]] || { echo "$L has a body of $b bytes, at most 1200"; exit 1; }
    grep -qx "when: design" "$L" || { echo "$L is not when: design"; exit 1; }
    for t in stylua selene format lint; do grep -qE "^tags: \[(.*, )?$t(, .*)?\]\$" "$L" || { echo "$L lacks the tag $t"; exit 1; }; done
    grep -qxF "check: did '"'"'stylua --check'"'"' and '"'"'selene'"'"' run clean over the issue'"'"'s folder (acceptance/, experiments/) on the prep commit?" "$L" ||
      { echo "$L lost the captured check question"; exit 1; }'

check "AC2: the lesson says what the gate's stages read and fail on (every .luau of each .tracker, acceptance/ and experiments/ included; a diff, an error or a warning), and that nothing a prep runs earlier does (tests/run, ./zn check, ./zn promote-check, the Claude Code edit hook, which no other CLI runs and which misses a shell command, a copy or a merge), that they read no .sh and no .luau.txt, and that under ./zn dispatch the prep gate merges on CI, which runs no gate (c0359)" \
  bash -c 'has "$L" "full gate" "every \`.luau\`" "\`.tracker/\`" "\`acceptance/\` and \`experiments/\` included" "a diff, an error or a warning" \
    "\`tests/run\`" "\`./zn check\`" "\`./zn promote-check\`" "the Claude Code edit hook (no other CLI runs it)" "a shell command, a copy or a merge" "no \`.sh\` and no \`.luau.txt\`" \
    "Under \`./zn dispatch\` the prep gate merges on CI, which runs no gate, so a failing folder reaches main (c0359)"'

check "AC3: the lesson tells the incident: c0261's prep PR #259 at its merge gate on 2026-11-09, all 12 acceptance specs unformatted, invalid '\\{' escapes, an unused require, the gate failing at format and lint" \
  bash -c 'has "$L" "c0261" "PR #259" "2026-11-09" "all 12 acceptance specs unformatted" "\`'"'"'\\{'"'"'\`" "unused require" "failed at format and lint"'

check "AC4: the lesson's How to apply gives the command from the repository root, after writing the specs (before the mutation check and the review), right before the prep commit and again after any later change, formats by the folder's path until both exit 0, says a warning alone fails selene, and names zz-test/format-tracker-specs-by-path" \
  bash -c 'has "$L" "**How to apply:** from the repository root" "after writing the specs (before the mutation check and the review)" "right before the prep commit" "again after any later change to a \`.luau\` in the folder" \
    "\`d=\$(./zn find <id>); stylua \"\$d\"; stylua --check \"\$d\" && selene --quiet \"\$d\"\`" "until both exit 0" "selene exits 1 on a warning alone" \
    "\`stylua .\` skips \`.tracker/\`" "(zz-test/format-tracker-specs-by-path)"'

check "AC5: z-design step 4 tells the prep to run the two stages over the issue's folder before the mutation check and the review, and step 6 before the prep commit, each with the lesson's command and naming the lesson" \
  bash -c 'S=skills/z-design/SKILL.md
    s4=$(awk "/^## 4\\. Write the executable acceptance/{f=1;next} /^## /{f=0} f" "$S")
    [[ -n $s4 ]] || { echo "$S has no section ## 4. Write the executable acceptance"; exit 1; }
    w4="- **Format and lint the folder** before the mutation check and the review: \`d=\$(./zn find <id>); stylua \"\$d\"; stylua --check \"\$d\" && selene --quiet \"\$d\"\` from the repository root, until both exit 0 (step 6 runs it again on the committed bytes; lesson z-design/prep-specs-pass-format-and-lint)."
    l4=$(printf "%s\n" "$s4" | grep -nxF -- "$w4" | cut -d: -f1)
    [[ -n $l4 ]] || { echo "step 4 lacks the sentence: $w4"; exit 1; }
    m4=$(printf "%s\n" "$s4" | grep -n "^- \*\*Mutation check\*\*" | cut -d: -f1)
    [[ -n $m4 && $l4 -lt $m4 ]] || { echo "the step-4 sentence is not before the Mutation check bullet"; exit 1; }
    sec=$(awk "/^## 6\\. Commit and hand off/{f=1;next} /^## /{f=0} f" "$S")
    [[ -n $sec ]] || { echo "$S has no section ## 6. Commit and hand off"; exit 1; }
    want="  - Before the prep commit, run the gate'"'"'s format and lint stages over the issue'"'"'s folder from the repository root, \`d=\$(./zn find <id>); stylua \"\$d\"; stylua --check \"\$d\" && selene --quiet \"\$d\"\`, until both exit 0, and again after any later change to a \`.luau\` there: the full gate reads every \`.luau\` in it, and nothing earlier in a prep does (lesson z-design/prep-specs-pass-format-and-lint)."
    line=$(printf "%s\n" "$sec" | grep -nxF -- "$want" | cut -d: -f1)
    [[ -n $line ]] || { echo "step 6 lacks the sentence: $want"; exit 1; }
    rep=$(printf "%s\n" "$sec" | grep -n "^- \*\*Report\*\*" | cut -d: -f1)
    com=$(printf "%s\n" "$sec" | grep -n "^- \*\*Commit\*\*" | cut -d: -f1)
    [[ -n $com && -n $rep && $line -gt $com && $line -lt $rep ]] || { echo "the sentence is not under the Commit bullet of step 6"; exit 1; }'

check "AC6: the mechanisms the lesson names still hold: the gate's two stages over LUAU_DIRS, z-nile's roots list its .tracker, no engine module and not tests/run runs stylua or selene, the edit hook reads only an edited file_path, and zz-test/format-tracker-specs-by-path exists" \
  bash -c 'G="$ZN_ROOT/z-nile/check.sh"
    has "$G" "stylua --check \"\${LUAU_DIRS[@]}\"" "selene --quiet \"\${LUAU_DIRS[@]}\"" || exit 1
    (cd "$ZN_ROOT" && lune run z-nile/roots -- --luau-dirs) | tr " " "\n" | grep -qx "z-nile/.tracker" || { echo "z-nile/roots --luau-dirs no longer lists z-nile/.tracker"; exit 1; }
    hit=$(grep -lE "\\b(stylua|selene)\\b" engine/*.luau tests/run.luau 2>/dev/null)
    [[ -z $hit ]] || { echo "these now run stylua or selene, so the lesson is wrong about them: $hit"; exit 1; }
    has "$ZN_ROOT/scripts/hooks/post-edit.sh" "\"file_path\"" "stylua \"\$file\"" "selene --quiet \"\$file\"" || exit 1
    [[ -f skills/zz-test/lessons/format-tracker-specs-by-path.md ]] || { echo "zz-test/format-tracker-specs-by-path is gone"; exit 1; }'

check "AC7: this issue's own folder passes the gate's format and lint stages, read the way the lesson says (from the repository root, by ./zn find's path)" \
  bash -c 'cd "$ZN_ROOT" || exit 1
    d=$(./zn find c0292) && [[ -d $d ]] || { echo "./zn find c0292 printed no folder: $d"; exit 1; }
    stylua --check "$d" && selene --quiet "$d"'

check "AC8: the lesson and its harvest note pass ./zn lessons --check and --uncovered c0292 (and --unattributed once c0136 exists), the note is (erred z-design), c0292 is on its sources line, and design lists and reads it" \
  bash -c 'Z="$ZN_ROOT/zn"; "$Z" lessons --check && "$Z" lessons --uncovered c0292 || exit 1
    if grep -q unattributed "$ZN_ROOT/z-nile/engine/lessons.luau"; then "$Z" lessons --unattributed c0292 || exit 1; fi
    grep -qE "^- note .*\(erred z-design\): (.*, )?z-design/prep-specs-pass-format-and-lint(,.*)?\$" "$H" || { echo "no (erred z-design) note naming the lesson in $H"; exit 1; }
    idx=$("$Z" lessons --when design); full=$("$Z" lessons --when design --full)
    grep -q "^- z-design/prep-specs-pass-format-and-lint (design, " <<<"$idx" || { echo "not listed by --when design"; exit 1; }
    grep -q "^== .*skills/z-design/lessons/prep-specs-pass-format-and-lint.md" <<<"$full" || { echo "not read by --when design --full"; exit 1; }
    "$Z" lessons --skill z-design --full prep-specs-pass-format-and-lint | grep -qE "^sources:.*c0292" || { echo "c0292 is not on the sources line"; exit 1; }'

check "AC9: once c0181 has landed (lessons.luau knows enforced_by), the lesson carries a state and ./zn lessons --check --policy --item c0292 passes" \
  bash -c 'if ! grep -q enforced_by "$ZN_ROOT/z-nile/engine/lessons.luau"; then echo "c0181 has not landed: nothing to check"; exit 0; fi
    grep -qE "^(enforced_by|not_codifiable):" "$L" || { echo "c0181 has landed: the lesson needs enforced_by or not_codifiable"; exit 1; }
    "$ZN_ROOT/zn" lessons --check --policy --item c0292'

finish
