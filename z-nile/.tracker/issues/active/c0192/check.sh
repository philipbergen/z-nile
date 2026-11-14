#!/usr/bin/env bash
# Acceptance checks for c0192. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
# The lesson is text, and c0181 turns a lesson's paragraph into a field, so these checks read it here and no promoted
# spec pins its words (the same choice as c0193's AC9). Each runs from z-nile/ (the item's project home).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the lesson zz-review/bound-every-probe is short (16 lines, a body of at most 1,200 bytes), reaches design and build, and keeps the captured question (every command started outside the spec runner stops on its own within a minute, and when I stop)" \
  bash -c 'L=skills/zz-review/lessons/bound-every-probe.md
    [ -f "$L" ] || { echo "no $L"; exit 1; }
    n=$(( $(wc -l < "$L") )); [ "$n" -le 16 ] || { echo "$L has $n lines, at most 16"; exit 1; }
    b=$(( $(sed -e "1,/^---\$/d" "$L" | wc -c) )); [ "$b" -le 1200 ] || { echo "$L has a body of $b bytes, at most 1200 (c0181 cap for a partly enforced lesson)"; exit 1; }
    grep -qx "when: both" "$L" || { echo "$L is not when: both"; exit 1; }
    grep -q "^tags: .*process" "$L" && grep -q "^tags: .*probes" "$L" || { echo "$L lacks the tags process and probes"; exit 1; }
    grep -q "^check: .*outside the spec runner.*stop on its own within a minute, and when I stop?$" "$L" || { echo "$L lost the captured check question"; exit 1; }'
check "AC2: the lesson states the bounded-command rule in the same words as AGENTS.md (the sentence c0191 pins), read from AGENTS.md as it stands" \
  bash -c 'L=skills/zz-review/lessons/bound-every-probe.md
    a=$(<"$ZN_ROOT/AGENTS.md")
    case "$a" in *"Run every probe"*"when you do."*) ;; *) echo "AGENTS.md carries no bounded-command rule (c0191 not landed?)"; exit 1;; esac
    s=${a#*Run every probe}; s="Run every probe${s%%when you do.*}when you do."
    l=$(<"$L"); case "$l" in *"$s"*) ;; *) echo "the lesson does not carry AGENTS.md rule word for word: $s"; exit 1;; esac'
check "AC3: the lesson points at its enforcers on one Enforced by line, each a file that exists (the meta case, runner, hook, reaper, AGENTS.md, c0191's docs spec), carries the incident (PR #125, 14 h) and why an alarm is no bound, and says how to apply it (the exit codes 124 and 125, the hook, the limit a longer step names)" \
  bash -c 'L=skills/zz-review/lessons/bound-every-probe.md
    E=$(grep "^\*\*Enforced by\*\*" "$L") || { echo "no Enforced by line"; exit 1; }
    for p in "$ZN_ROOT/z-nile/tests/meta/bound-every-probe.spec.luau" "$ZN_ROOT/z-nile/lib/bounded.pl" "$ZN_ROOT/scripts/hooks/pre-bash.sh" "$ZN_ROOT/z-nile/engine/reap.luau" "$ZN_ROOT/AGENTS.md" "$ZN_ROOT/z-nile/tests/acceptance/c0191/docs.spec.luau"; do
      f=${p#"$ZN_ROOT/"}
      case "$E" in *"$f"*) ;; *) echo "Enforced by does not name $f"; exit 1;; esac
      [ -f "$p" ] || { echo "$f does not exist"; exit 1; }
    done
    for w in "PR #125" "14 h" "alarm" "launcher" "124 (wall clock)" "125 (CPU)" "get round the hook" "the limit its step names"; do grep -qF "$w" "$L" || { echo "the lesson does not say: $w"; exit 1; }; done'
check "AC4: the lesson and its harvest note pass ./zn lessons --check and --uncovered (and --unattributed once c0136 exists), c0192 is on its sources line, and it is listed for design and for build" \
  bash -c 'Z="$ZN_ROOT/zn"; "$Z" lessons --check && "$Z" lessons --uncovered c0192 || exit 1
    if grep -q unattributed "$ZN_ROOT/z-nile/engine/lessons.luau"; then "$Z" lessons --unattributed c0192 || exit 1; fi
    for w in design build; do "$Z" lessons --when $w --full | grep "^== .*skills/zz-review/lessons/bound-every-probe.md" > /dev/null || { echo "not listed for --when $w"; exit 1; }; done
    "$Z" lessons --skill zz-review --full bound-every-probe | grep -E "^sources:.*c0192" > /dev/null || { echo "c0192 is not on the sources line"; exit 1; }'

check "AC5: the executor-written meta case [zz-review/bound-every-probe] (the lesson's enforcing ref, run in the gate) exists, shows each of its jobs (the hook check, the wrapper, AGENTS.md, the lesson, the file test, the sentence: six words in the file) and passes in the spec runner, and once c0181 has landed the lesson names it as enforced_by with enforced: part" \
  bash -c 'S="$ZN_ROOT/z-nile/tests/meta/bound-every-probe.spec.luau"; L=skills/zz-review/lessons/bound-every-probe.md
    [ -f "$S" ] || { echo "no meta spec"; exit 1; }
    grep -qF "[zz-review/bound-every-probe]" "$S" || { echo "the meta spec has no case named for the lesson"; exit 1; }
    for w in "boundcmd.check(" "zn run --time" "\"AGENTS.md\"" "bound-every-probe.md" "isFile" "when you do."; do grep -qF -- "$w" "$S" || { echo "the meta spec does not do its job: it lacks $w"; exit 1; }; done
    if grep -q enforced_by "$ZN_ROOT/z-nile/engine/lessons.luau"; then
      grep -q "^enforced_by: z-nile/tests/meta/bound-every-probe.spec.luau :: .\[zz-review/bound-every-probe\]" "$L" && grep -qx "enforced: part" "$L" || { echo "c0181 has landed: the lesson needs enforced_by naming the meta case, and enforced: part"; exit 1; }
    fi
    lune run tests/run -- "$S"'

finish
