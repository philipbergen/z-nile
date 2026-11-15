#!/usr/bin/env bash
# E4 (c0292 prep): the prototype and the mutation check. In a throwaway clone of this worktree (mktemp -d, removed at
# the end) with the item folder copied in as it stands, the reference lesson, the step-6 sentence and the harvest note
# make check.sh pass whole; each mutant must fail its named AC on an assertion message. Then the promoted specs that
# walk the lessons or read z-design's SKILL.md run on the prototype. Writes nothing outside its folder.
#   ./zn run --time 1800 -- bash z-nile/.tracker/issues/c0292/experiments/E4-prototype.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd -P)"
top="$(git -C "$here" rev-parse --show-toplevel)"
t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT
# the clone must never see the dispatched step's broker, git wrapper, run state or credential
# (lesson z-design/clone-experiments-drop-the-step-environment, c0272's prep)
for v in $(compgen -e | grep '^ZN_'); do unset "$v"; done
unset GH_CONFIG_DIR
PATH=$(tr ':' '\n' <<<"$PATH" | grep -v '/z-nile/bin$' | paste -sd: -)
export PATH="$HOME/.rokit/bin:$PATH"
git clone -q --no-local "$top" "$t/repo"
I=z-nile/.tracker/issues/c0292
rm -rf "$t/repo/$I" && cp -R "$top/$I" "$t/repo/$I"
cd "$t/repo" || exit 1
case "$(git remote get-url origin)" in "$top"|"$top/") ;; *) echo "E4: odd origin"; exit 2 ;; esac
# the copied item folder is the clone's base, so each mutant's reset returns to it (a scratch commit in the clone only)
git add -A "$I" && git -c user.name=e4 -c user.email=e4@example.invalid commit -qm "E4 base: c0292 item folder" || exit 2
L=z-nile/skills/z-design/lessons/prep-specs-pass-format-and-lint.md
S=z-nile/skills/z-design/SKILL.md
NOTE='- note c0261'"'"'s prep PR #259 failed its merge gate at format and lint: its 12 sequestered specs had never been through stylua or selene (the capture of c0292) (erred z-design): z-design/prep-specs-pass-format-and-lint'
apply() {
  git reset -q --hard && git clean -qfd z-nile/skills 2>/dev/null
  rm -f "$L" z-nile/skills/zz-test/lessons/prep-specs-pass-format-and-lint.md
  if [[ -f $top/$I/harvest.md ]]; then grep -vF 'prep-specs-pass-format-and-lint' "$top/$I/harvest.md" > "$I/harvest.md"; else : > "$I/harvest.md"; fi
  cp "$I/experiments/ref-lesson.md.txt" "$L" && echo "$NOTE" >> "$I/harvest.md"
  python3 - "$S" "$I/experiments/ref-skill-step6.txt" "$I/experiments/ref-skill-step4.txt" <<'PY'
import sys
p, r6, r4 = sys.argv[1:]
s = open(p).read(); add6 = open(r6).read(); add4 = open(r4).read()
i = s.index("\n- **Commit** "); j = s.index("\n", i + 1)
s = s[: j + 1] + add6 + s[j + 1 :]
k = s.index("\n- **Mutation check**")
open(p, "w").write(s[: k + 1] + add4 + s[k + 1 :])
PY
}
# sub <file> <old> <new>: replace the literal text; exit 3 when it is not there (the mutant did not apply)
sub() {
  python3 - "$@" <<'PY'
import sys
p, a, b = sys.argv[1:]
s = open(p).read()
if a not in s:
    sys.exit(3)
open(p, "w").write(s.replace(a, b, 1))
PY
}
run() { bash "$I/check.sh" 2>&1; }
apply
out=$(run)
echo "$out" | grep -E '^(PASS|FAIL)|criteria passed' | cut -c1-12
grep -q '9/9 criteria passed' <<<"$out" && echo "E4 prototype PASS: 9/9" || { echo "E4 prototype FAIL"; echo "$out" | grep -A4 '^FAIL'; }
mut() {
  local name=$1 ac=$2 o
  shift 2
  apply
  "$@" || { echo "$name: could not apply"; return; }
  o=$(run)
  if grep -q "^FAIL  $ac:" <<<"$o"; then
    echo "$name: killed by $ac ($(echo "$o" | awk -v a="FAIL  $ac:" 'index($0,a)==1{f=1;next} f&&/^(PASS|FAIL) /{exit} f' | grep -vE '^ *(lessons|harvest|c0292): ' | head -1 | sed 's/^ *//' | cut -c1-110))"
  else
    echo "$name: SURVIVED $ac"
  fi
}
mut M1-when-build AC1 sub "$L" 'when: design' 'when: build'
mut M2-check-drops-experiments AC1 sub "$L" '(acceptance/, experiments/)' '(acceptance/)'
mut M3-no-selene-tag AC1 sub "$L" 'selene, ' ''
mut M4-long-body AC1 sub "$L" 'failed at format and lint.' "failed at format and lint.$(printf ' padding%.0s' $(seq 1 3))"
mut M5-experiments-not-read AC2 sub "$L" ', the issue'"'"'s `acceptance/` and `experiments/` included' ''
mut M6-warning-passes AC2 sub "$L" 'a diff, an error or a warning' 'a diff or an error'
mut M7-promote-check-covers AC2 sub "$L" ' or `./zn promote-check`' ''
mut M8-hook-covers-all AC2 sub "$L" ', not a shell command, a copy or a merge' ''
mut M9-check-sh-linted AC2 sub "$L" ' They read no `.sh` and no `.luau.txt`.' ''
mut M10-no-pr AC3 sub "$L" 'PR #259' 'a PR'
mut M11-no-escapes AC3 sub "$L" "invalid \`'\\{'\` escapes in plain strings and " ''
mut M12-stylua-dot AC4 sub "$L" 'stylua "$d"; stylua --check "$d" && selene --quiet "$d"' 'stylua .; stylua --check . && selene --quiet .'
mut M13-once-only AC4 sub "$L" ' and again after any later change to a `.luau` in the folder' ''
mut M14-no-warning-note AC4 sub "$L" ' (selene exits 1 on a warning alone)' ''
mut M15-check-only-stylua AC4 sub "$L" ' && selene --quiet "$d"' ''
mut M16-no-step6 AC5 git checkout -q -- "$S"
mut M17-sentence-in-step4 AC5 bash -c 'python3 - "$0" "$1" <<PY
import sys
p, r = sys.argv[1:]
s = open(p).read(); add = open(r).read()
s = s.replace(add, "", 1)
i = s.index("\n- **Dry-run the promotion**")
open(p, "w").write(s[: i + 1] + add + s[i + 1 :])
PY' "$S" "$I/experiments/ref-skill-step6.txt"
mut M18-step6-no-lesson AC5 sub "$S" ' (lesson z-design/prep-specs-pass-format-and-lint).' '.'
mut M19-gate-drops-lint AC6 sub z-nile/check.sh 'par_start "lint (selene)" selene --quiet "${LUAU_DIRS[@]}"' 'par_start "lint (selene)" selene --quiet z-nile'
mut M20-promote-check-formats AC6 sub z-nile/engine/main.luau 'local args = { "run", "tests/run", "--", "tests/meta/architecture.spec.luau" }' 'local args = { "run", "tests/run", "--", "tests/meta/architecture.spec.luau" } -- then stylua'
mut M21-hook-gone AC6 sub scripts/hooks/post-edit.sh 'selene --quiet "$file"' 'true'
mut M22-unformatted-spec AC7 bash -c 'printf "local  x =1\nreturn x\n" > "$0/experiments/E9.luau"' "$I"
mut M23-warning-only AC7 bash -c 'printf "local a = 1\nlocal function f()\n\tlocal a = 2\n\treturn a\nend\nreturn { a, f }\n" > "$0/experiments/E9.luau"' "$I"
mut M24-no-note AC8 bash -c 'grep -vF prep-specs-pass "$0" > "$0.x"; mv "$0.x" "$0"' "$I/harvest.md"
mut M25-note-ungrouped AC8 sub "$I/harvest.md" ' (erred z-design): ' ': '
mut M26-wrong-skill AC8 bash -c 'mkdir -p z-nile/skills/zz-test/lessons && mv "$0" z-nile/skills/zz-test/lessons/ && sed -i.b "s#z-design/prep-specs#zz-test/prep-specs#" "$1" && rm -f "$1.b"' "$L" "$I/harvest.md"
mut M27-dispatch-unsaid AC2 sub "$L" ' Under `./zn dispatch` the prep gate merges on CI, which runs no gate, so a failing folder reaches main (c0359).' ''
mut M28-hook-every-cli AC2 sub "$L" 'the Claude Code edit hook (no other CLI runs it)' 'the edit hook'
mut M29-lesson-no-early-run AC4 sub "$L" 'after writing the specs (before the mutation check and the review), ' ''
mut M30-from-the-home AC4 sub "$L" 'from the repository root' 'from the project home'
mut M31-not-before-commit AC4 sub "$L" ' right before the prep commit,' ''
mut M32-run-once AC4 sub "$L" 'until both exit 0 ' ''
mut M33-gate-drops-format AC6 sub z-nile/check.sh 'stylua --check "${LUAU_DIRS[@]}"' 'stylua --check z-nile'
mut M34-roots-drop-tracker AC6 sub z-nile/roots.luau 'table.insert(dirs, p.root)' 'local _ = p.root'
mut M35-zz-test-lesson-gone AC6 git mv z-nile/skills/zz-test/lessons/format-tracker-specs-by-path.md z-nile/skills/zz-test/lessons/format-tracker-specs.md
mut M36-no-format-tag AC1 sub "$L" ' format,' ''
mut M37-no-lint-tag AC1 sub "$L" ' lint,' ''
mut M38-no-step4 AC5 sub "$S" "$(cat "$I/experiments/ref-skill-step4.txt")
" ''
mut M39-step4-after-mutation AC5 bash -c 'python3 - "$0" "$1" <<PY
import sys
p, r = sys.argv[1:]
s = open(p).read(); add = open(r).read()
s = s.replace(add, "", 1)
i = s.index("\n- **Dry-run the promotion**")
open(p, "w").write(s[: i + 1] + add + s[i + 1 :])
PY' "$S" "$I/experiments/ref-skill-step4.txt"
rm -f "$I/experiments/E9.luau"
apply
echo "== specs that walk the lessons or read z-design's SKILL.md, on the prototype"
cd z-nile && lune run tests/run -- tests/acceptance/c0111/lesson-format.spec.luau tests/acceptance/c0111/harvest.spec.luau \
  tests/acceptance/c0111/skill-docs.spec.luau tests/acceptance/c0111/lessons-cli.spec.luau tests/acceptance/c0111/prompt-lessons.spec.luau \
  tests/acceptance/c0115/lessons.spec.luau tests/acceptance/c0119/scope-lessons.spec.luau tests/tooling/lessons-hidden.spec.luau \
  tests/acceptance/c0043/ticket-prep.spec.luau tests/acceptance/c0047/override-check.spec.luau tests/acceptance/c0115/docs.spec.luau \
  tests/acceptance/c0115/layout.spec.luau tests/acceptance/c0115/readme.spec.luau tests/acceptance/c0116/docs.spec.luau \
  tests/acceptance/c0119/scope-docs.spec.luau tests/acceptance/c0120/docs.spec.luau tests/acceptance/c0172/merge.spec.luau \
  tests/acceptance/c0191/docs.spec.luau tests/tooling/dispatch-texts.spec.luau 2>&1 | tail -6
