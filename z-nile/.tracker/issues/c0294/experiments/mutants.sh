#!/usr/bin/env bash
# E2: the mutation check. For each row of Rules and mutants, rebuild the prototype (proto.sh), apply the mutant, run
# ./zn check c0294 in the prototype, and require the row's criterion to FAIL with an assertion message (the last
# line of its FAIL block: the lessons commands print their own status lines first). A row marked "pass" must PASS.
# Run it only on a proto-c0294 worktree (argument 1), under ./zn run, with stdin closed.
# It changes only files of that worktree, moves no ref and commits nothing.
set -uo pipefail
P=${1:?prototype worktree}
X="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
[[ $P == */.worktree/proto-c0294 ]] || { echo "refusing: $P is not a proto-c0294 worktree" >&2; exit 1; }
L="$P/z-nile/skills/z-ticket/lessons/moved-part-rewrites-the-owner.md"
H="$P/z-nile/.tracker/issues/c0294/harvest.md"
E="$P/z-nile/engine/lessons.luau"
sub() { # sub <file> <perl substitution>: fails when the substitution changed nothing
  local before; before=$(shasum <"$1")
  perl -0pi -e "$2" "$1"
  [[ $(shasum <"$1") != "$before" ]] || { echo "  mutant did not apply: $2" >&2; return 1; }
}
REF=ref-lesson.md.txt
mutant() { # mutant <id> <AC> <description> <command...>
  local id=$1 ac=$2 what=$3; shift 3
  rm -f "${L%/*}/moved-part.md"
  "$X/proto.sh" "$P" "$REF" >/dev/null
  git -C "$P" checkout -q -- z-nile/engine/lessons.luau
  if ! "$@"; then echo "$id NOT APPLIED: $what"; return; fi
  local out; out=$(cd "$P" && ./zn check c0294 </dev/null 2>&1)
  local block; block=$(awk -v a="FAIL  $ac:" 'index($0,a)==1{f=1;next} f&&/^(PASS|FAIL|----)/{exit} f{print}' <<<"$out")
  if grep -q "^FAIL  $ac:" <<<"$out"; then echo "$id killed by $ac ($what): $(tail -1 <<<"$block" | sed 's/^ *//')"
  else echo "$id SURVIVED $ac ($what)"; fi
}
expect_pass() { # expect_pass <id> <AC> <description> <command...>: the change is allowed, so the criterion passes
  local id=$1 ac=$2 what=$3; shift 3
  "$X/proto.sh" "$P" "$REF" >/dev/null
  "$@" || { echo "$id NOT APPLIED: $what"; return; }
  local out; out=$(cd "$P" && ./zn check c0294 </dev/null 2>&1)
  if grep -q "^PASS  $ac:" <<<"$out"; then echo "$id passes $ac as it should ($what)"
  else echo "$id WRONGLY FAILS $ac ($what)"; fi
}
mutant M1 AC1 "lesson at another path" mv "$L" "${L%/*}/moved-part.md"
mutant M2 AC1 "when: design" sub "$L" 's/^when: both$/when: design/m'
mutant M3 AC5 "when: design (build listing)" sub "$L" 's/^when: both$/when: design/m'
mutant M4 AC1 "tag dependencies dropped" sub "$L" 's/capture, dependencies, scope/capture, scope/'
mutant M5 AC1 "captured question reworded" sub "$L" 's/name the new owner/name its owner/'
mutant M6 AC1 "added clause dropped" sub "$L" 's/ And is each ticket this capture cannot edit named to the user\?//'
mutant M7 AC1 "body padded over 1,200 bytes" sub "$L" 's/(PR #281\)\.)\n/$1 '"$(printf 'x%.0s' $(seq 1 140))"'\n/'
mutant M8 AC1 "a 13th line" sub "$L" 's/\z/\n\nmore\n/'
mutant M9 AC1 "another title" sub "$L" 's/^title: .*$/title: Moved parts rewrite owners/m'
mutant M10 AC2 "edge direction reversed" sub "$L" 's/edge from B to A \(B waits for A\)/edge from A to B (A waits for B)/'
mutant M11 AC2 "F5 placed in round 2" sub "$L" 's/round 1, F5/round 2, F5/'
mutant M12 AC2 "the stranded outcome dropped" sub "$L" 's/c0257.s captured "orders tickets and rafts by the order c0249 defines" was left/c0257 was left/'
mutant M13 AC3 "no Owners line" sub "$L" 's/, and an Owners line for what you settle beyond it//'
mutant M14 AC3 "outcomes not walked in the new order" sub "$L" 's/Walk its outcomes in the new order, move/Move/'
mutant M15 AC3 "uneditable tickets not named to the user" sub "$L" 's/, and name to the user each ticket whose text it cannot rewrite \(past draft, or on a prep branch, as c0276.s Non-goal was in draft PR #281\)//'
mutant M15b AC3 "the land wording put back" sub "$L" 's/each ticket whose text it cannot rewrite \(past draft, or on a prep branch, as/each ticket `.\/zn land` cannot edit (one being prepared, as/'
mutant M16 AC5 "no harvest note" sub "$H" 's/^- note .*moved-part-rewrites-the-owner\n//m'
mutant M17 AC5 "note without its step" sub "$H" 's/ \(erred z-ticket\)//'
mutant M19 AC1 "an extra sentence between the question and the clause" sub "$L" 's/still be built\? And is each/still be built? Also, is it ranked? And is each/'
mutant M20 AC3 "not in the same capture" sub "$L" 's/for each such answer, in the same capture, add/for each such answer, add/'
mutant M21 AC3 "a decision line that does not quote the option" sub "$L" 's/a decision line that quotes the option picked/a decision line/'
mutant M22 AC4 "the capture's paraphrase put back as the quote" sub "$L" 's/"orders tickets and rafts by the order c0249 defines"/"orders by the order c0249 defines"/'
mutant M23 AC2 "round 1's overturned fix told as the outcome" sub "$L" 's/c0249 took its rank order, lost work first stayed c0290.s,/c0249 took that part too,/'
REF=ref-lesson-c0181-first.md.txt
expect_pass M24 AC1 "the c0181-first text plus a distinct_from: line" sub "$L" 's/^(not_codifiable: .*)$/$1\ndistinct_from: z-ticket\/split-designs-name-each-owner/m'
mutant M25 AC1 "the c0181-first text plus a 13th line" sub "$L" 's/\z/\nmore\n/'
REF=ref-lesson.md.txt
mutant M18 AC6 "c0181 landed, lesson has no not_codifiable line" sub "$E" 's/\A/-- not_codifiable (mutant M18)\n/'
rm -f "${L%/*}/moved-part.md"
"$X/proto.sh" "$P" "$REF" >/dev/null
git -C "$P" checkout -q -- z-nile/engine/lessons.luau
