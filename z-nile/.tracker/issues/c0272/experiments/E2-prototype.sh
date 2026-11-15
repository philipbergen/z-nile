#!/usr/bin/env bash
# E2: the prototype and the mutation check. In a throwaway clone of this worktree (mktemp -d, removed at the end)
# with the item folder and the lessons copied in as they stand, the reference lesson and its harvest note make
# check.sh pass whole, and each mutant fails the named AC on an assertion. Writes nothing outside the folder.
# Run: ./zn run --time 2400 -- bash E2-prototype.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd -P)"
top="$(git -C "$here" rev-parse --show-toplevel)"
t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT
# a dispatched step's publish broker pushes to the real origin: the clone must never see it, the step's git
# wrapper, run state or credential (lesson z-design/clone-experiments-drop-the-step-environment)
for v in $(compgen -e | grep '^ZN_'); do unset "$v"; done
unset GH_CONFIG_DIR
PATH=$(tr ':' '\n' <<<"$PATH" | grep -v '/z-nile/bin$' | paste -sd: -)
git clone -q --no-local "$top" "$t/repo"
I=z-nile/.tracker/issues/c0272
rm -rf "$t/repo/$I" && cp -R "$top/$I" "$t/repo/$I"
cp "$top"/z-nile/skills/z-design/lessons/*.md "$t/repo/z-nile/skills/z-design/lessons/"
cd "$t/repo" || exit 1
L=z-nile/skills/z-design/lessons/superseding-prep-hands-over-the-claim.md
E=z-nile/engine/main.luau
NOTE='- note PR #256 was closed with a comment that reached nobody, and the agent holding the claim on c0264 kept designing (the capture of c0272) (erred z-design): z-design/superseding-prep-hands-over-the-claim'
apply() {
  rm -f z-nile/skills/zz-rules/lessons/superseding-prep-hands-over-the-claim.md
  cp "$I/experiments/ref-lesson.md.txt" "$L" && grep -vF 'superseding-prep-hands-over-the-claim' "$I/harvest.md" > "$t/h" &&
    cat "$t/h" > "$I/harvest.md" && echo "$NOTE" >> "$I/harvest.md"
  git checkout -q -- "$E"
}
# sub <file> <old> <new>: replace the literal text, and fail when it is not there (the mutant did not apply)
sub() {
  python3 - "$@" <<'PY'
import sys
p, a, b = sys.argv[1:]
s = open(p).read()
if a not in s:
    sys.exit(3)
open(p, "w").write(s.replace(a, b))
PY
}
run() { bash "$I/check.sh" 2>&1; }
apply
out=$(run)
echo "$out" | grep -E '^(PASS|FAIL)|criteria passed'
echo "$out" | grep -q '6/6 criteria passed' && echo "E2 prototype PASS: 6/6" || echo "E2 prototype FAIL"
# mut <name> <AC that must fail> <command and args that break the prototype>
mut() {
  local name=$1 ac=$2
  shift 2
  apply
  "$@" || { echo "$name: could not apply"; return; }
  local o
  o=$(run)
  if echo "$o" | grep -q "^FAIL  $ac:"; then
    echo "$name: killed by $ac ($(echo "$o" | awk -v a="FAIL  $ac:" 'index($0,a)==1{f=1;next} f&&/^(PASS|FAIL) /{exit} f' | grep -vE '^ *(lessons|harvest): ' | head -1 | sed 's/^ *//'))"
  else
    echo "$name: SURVIVED $ac"
  fi
}
mut M1-when-build AC1 sub "$L" 'when: design' 'when: build'
mut M1b-when-build AC5 sub "$L" 'when: design' 'when: build'
mut M2-question-loses-old-pr AC1 sub "$L" 'the claim, the issue and the old PR?' 'the claim and the issue?'
mut M3-tags-drop-claims AC1 sub "$L" 'tags: [coordination, claims, process]' 'tags: [coordination, process]'
mut M4-body-over-cap AC1 sub "$L" 'ends nothing by itself' "ends nothing by itself$(printf '%0210d' 0)"
mut M5-no-dispatched-step AC1 sub "$L" ', and did I stop the other worker if it is a dispatched step?' '?'
mut M6-no-pr-256 AC2 sub "$L" 'PR #256 ' ''
mut M7-no-whose-claim AC2 sub "$L" ' (zz-rules, Whose claim)' ''
mut M8-release-only AC3 sub "$L" ', then `./zn status <id> preparing` (' ' ('
mut M9-no-dispatch-stop AC3 sub "$L" '; stop a dispatched one with `./zn dispatch stop <id>`' ''
mut M10-no-holder-memory AC3 sub "$L" '`ls <main checkout>/.worktree/*/.cache/tracker-claim-<id>` and ' ''
mut M11-no-land AC3 sub "$L" ', landed from a `capture-<slug>` worktree with `./zn land`' ''
mut M12-old-pr-not-named AC3 sub "$L" "in the old PR's body and a comment (if it has one), then close it; and " ''
mut M13-claim-file-renamed AC4 sub "$E" 'tracker-claim-{' 'claim-{'
mut M14-no-note AC5 sub "$I/harvest.md" "$NOTE" ''
mut M15-note-no-erred AC5 sub "$I/harvest.md" ' (erred z-design): z-design/superseding' ': z-design/superseding'
mut M16-wrong-skill AC1 bash -c "mkdir -p z-nile/skills/zz-rules/lessons && mv $L z-nile/skills/zz-rules/lessons/"
mut M17-line-under-design AC3 sub "$L" 'directly under its `# <id>: <title>` heading' 'under its `## Design`'
mut M18-no-memory-removal AC3 sub "$L" "; then remove each superseded worktree's memory (\`rm <main checkout>/.worktree/<old>/.cache/tracker-claim-<id>\`), so the claim's only memory is in \`.worktree/<live branch>\`" ''
mut M19-search-from-cwd AC3 sub "$L" '`ls <main checkout>/.worktree/' '`ls .worktree/'
mut M20-take-over-in-old-worktree AC3 sub "$L" "in the live prep's worktree, \`./zn status <id> new\`" "in the old prep's worktree, \`./zn status <id> new\`"
mut M21-no-pr-case AC3 sub "$L" ' (if it has one)' ''
mut M22-land-usage-renamed AC4 sub "$E" '  land [-m <message>]' '  land-capture [-m <message>]'
mut M23-dispatch-usage-renamed AC4 sub "$E" 'dispatch stop|retry|status <id>' 'dispatch halt|retry|status <id>'
mut M24-judged-by-contents AC3 sub "$L" ", never judging by a memory's contents" ''
mut M25-no-worktree-list AC3 sub "$L" '`git worktree list | grep -e <id> -e <slug>`, ' ''
mut M26-not-newest-first AC3 sub "$L" ' (the newest on top)' ''
