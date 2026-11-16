#!/usr/bin/env bash
# E3: the prototype (the reference lesson, the step-1 bullet and the harvest note) passes check.sh, and each mutant
# fails the criterion its Rules and mutants row names. Works only in a fresh `mktemp -d` clone of this checkout's HEAD
# (with this item's folder copied over it), which it removes; it takes no path argument.
# Run: ./zn run --time 1800 -- z-nile/.tracker/issues/c0270/experiments/mutants.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd -P)"
item="$(cd "$here/.." && pwd -P)"
top="$(git -C "$here" rev-parse --show-toplevel)"
t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT
git clone -q --no-hardlinks "$top" "$t/c" || exit 1
c="$t/c"
rel="${item#"$top"/}"
rm -rf "${c:?}/$rel" && cp -R "$item" "$c/$rel"
L="$c/z-nile/skills/z-design/lessons/one-prep-per-issue.md"
S="$c/z-nile/skills/z-design/SKILL.md"
H="$c/$rel/harvest.md"
NOTE="- note c0264 prepped twice at once, PR #256's work lost (erred z-design): z-design/one-prep-per-issue"

prototype() {
  git -C "$c" checkout -q -- z-nile/skills z-nile/engine
  rm -f "$L"
  cp "$here/ref-lesson.md.txt" "$L"
  awk -v b="$here/ref-skill-bullet.txt" '{print} /^- If an issue is missing, create it first with the `z-ticket` skill\.$/{while((getline l < b)>0) print l}' "$S" >"$S.new" && mv "$S.new" "$S"
  cp "$item/harvest.md" "$H" 2>/dev/null || : >"$H"
  printf '%s\n' "$NOTE" >>"$H"
}
# the criteria check.sh fails, as "AC1 AC3" (or "none")
failing() {
  local out
  out=$(cd "$c" && bash "$rel/check.sh" 2>&1)
  local f
  f=$(grep -oE '^FAIL  AC[0-9]+' <<<"$out" | sed 's/FAIL  //' | tr '\n' ' ' | sed 's/ $//')
  echo "${f:-none}"
}
# sub <file> <old> <new>: replace the first occurrence of a fixed string, or fail the run
sub() {
  python3 -I - "$1" "$2" "$3" <<'PY' || { echo "mutant not applied: $2" >&2; exit 2; }
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
if old not in s:
    sys.exit(1)
open(p, "w").write(s.replace(old, new, 1))
PY
}
row() { # row <name> <expected>: run check.sh on the mutated prototype and compare
  local got
  got=$(failing)
  if [[ $got == "$2" ]]; then echo "killed  $1: $got"; else echo "WRONG   $1: expected $2, got $got"; fi
}

prototype
echo "prototype: $(failing)"

prototype; rm "$L"; row lesson-missing "AC1 AC2 AC3"
prototype; sub "$L" "when: design" "when: build"; row when-build "AC1 AC3"
prototype; sub "$L" "tags: [coordination, claims, process]" "tags: [coordination, process]"; row no-claims-tag "AC1"
prototype; sub "$L" " and \`./zn status <id>\` name another" " name another"; row question-loses-status "AC1"
prototype; sub "$L" "(\`'*<slug>*'\`), " ""; row check-no-slug "AC1"
prototype; sub "$L" "the PR search name the repository with \`--repo\`, " ""; row check-no-repo "AC1"
prototype; sub "$L" ", and \`git worktree list\` show no other worktree for it" ""; row check-no-worktree "AC1"
prototype; printf '%1300s\n' x >>"$L"; row body-over-cap "AC1"
prototype; mkdir -p "$c/z-nile/skills/zz-rules/lessons" && mv "$L" "$c/z-nile/skills/zz-rules/lessons/"
sed -i '' 's#z-design/one-prep-per-issue#zz-rules/one-prep-per-issue#' "$H"; row filed-under-zz-rules "AC1 AC2 AC3"; rm -f "$c/z-nile/skills/zz-rules/lessons/one-prep-per-issue.md"
prototype; sub "$L" "\`prep-readme-states-znile-intent\`" "the agent's branch"; row why-no-agent-branch "AC2"
prototype; sub "$L" "PR #256" "its PR"; sub "$L" "closed #256" "closed it"; row why-no-pr "AC2"
prototype; sub "$L" "(zz-rules, Whose claim)" "(zz-rules)"; row apply-no-whose-claim "AC2"
prototype; : >"$H"; row no-harvest-note "AC3"
prototype; sub "$H" " (erred z-design)" ""; row note-no-step-group "AC3"
prototype; sub "$S" "- **One prep per issue**" "- **One prep**"; row bullet-missing "AC4"
prototype; sub "$S" "' '*<slug>*'\`" "'\`"; row bullet-no-slug "AC4"
prototype; sub "$S" "gh pr list --repo \"\$(gh repo view --json nameWithOwner -q .nameWithOwner)\" --state all" "gh pr list --state all"; row bullet-no-repo "AC4"
prototype; sub "$S" "--state all --search" "--search"; row bullet-open-only "AC4"
prototype; sub "$S" ", and again whenever you resume a prep," ","; row bullet-no-resume "AC4"
prototype; sub "$S" "\`git worktree list | grep -e <id> -e <slug>\` and " ""; row bullet-no-worktree "AC4"
# design review 001 F1 to F4: what is yours, the claim, another prep, and what to do
prototype; sub "$S" "  - **Yours**: the branch this worktree is on and its PR, and every prototype branch or worktree your issue document names (and a worktree named after one, detached or not). Name each prototype you make in Unknowns & experiments, so that a resume knows it as yours.
" ""; row yours-deleted "AC4"
prototype; sub "$S" ", and every prototype branch or worktree your issue document names (and a worktree named after one, detached or not)" ""; row prototypes-not-yours "AC4"
prototype; sub "$S" " Name each prototype you make in Unknowns & experiments, so that a resume knows it as yours." ""; row prototypes-not-named "AC4"
prototype; sub "$S" "At a resume the claim alone proves nothing, because nothing records who made it: under \`ZN_DISPATCH=1\` it is the chain's, since the dispatcher starts z-design on a \`preparing\` issue only after its own chain's z-design step; in a terminal it is yours when this prep claimed it." "At a resume, a \`preparing\` claim you did not make is another prep's."; row claim-unconditional-at-resume "AC4"
prototype; sub "$S" "under \`ZN_DISPATCH=1\` it is the chain's, since the dispatcher starts z-design on a \`preparing\` issue only after its own chain's z-design step; " ""; row dispatcher-claim-removed "AC4"
prototype; sub "$S" "any other branch with an open PR or none," "any other branch with an open PR,"; row branch-without-pr-not-counted "AC4"
prototype; sub "$S" ", that holds a design of this issue (its copy of the issue document has a Design section or \`acceptance/\` files that main's lacks)" ""; row no-design-filter "AC4"
prototype; sub "$S" "Read the rest without counting it: a PR that only mentions the id, " "Read the rest without counting it: "; row every-pr-counted "AC4"
prototype; sub "$S" "A merged one is history." "A merged one is a prep under way."; row merged-counted "AC4"
prototype; sub "$S" "join another prep only with its owner's say (ask the user)" "join another prep only with its owner's say"; row ask-user-dropped "AC4"
prototype; sub "$S" ", or stop and take another issue" ""; row no-stop "AC4"
prototype; sub "$S" ", and a closed PR, whose comments say where its work went (follow it)" ""; row bullet-no-closed-pr "AC4"
prototype; sub "$S" "first read \`\$ZN_DISPATCH_DIR/answered-*.md\` and follow a ruling that names exactly the hits you find now. Otherwise " ""; row answers-not-read "AC4"
prototype; sub "$S" "Under \`ZN_DISPATCH=1\`, first read" "First read"; sub "$S" "Otherwise write the hits to \`\$ZN_DISPATCH_DIR/questions.md\` with the three choices that work, and stop: " "Otherwise ask the user: "; row bullet-no-headless "AC4"
prototype; sub "$S" "; the user keeps it, runs \`./zn dispatch stop <id>\` and carries it on in a terminal" ""; row no-keep-choice "AC4"
prototype; sub "$S" "; or the user rules that a hit is not a prep of this issue" ""; row no-not-a-prep-choice "AC4"
# the bullet, with its sub-bullets, moved out of step 1 (to the end of step 2)
prototype; python3 -I - "$S" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
i = s.index("- **One prep per issue**"); j = s.index("\n", i) + 1
while s.startswith("  ", j):
    j = s.index("\n", j) + 1
b = s[i:j]; s = s[:i] + s[j:]
k = s.index("\n## 3."); s = s[:k] + "\n" + b.rstrip("\n") + s[k:]
open(p, "w").write(s)
PY
row bullet-outside-step-1 "AC4"
# c0181 first: lessons.luau reads not_codifiable, and the lesson does not state it
prototype; printf '\n-- not_codifiable (c0270 mutant: c0181 has landed)\n' >>"$c/z-nile/engine/lessons.luau"; row c0181-first-no-state "AC5"
# c0181 first: the lesson states it and the harvest does not record it
prototype; printf '\n-- not_codifiable (c0270 mutant: c0181 has landed)\n' >>"$c/z-nile/engine/lessons.luau"
sub "$L" "tags: [coordination, claims, process]" "tags: [coordination, claims, process]
not_codifiable: whether a session searched for another prep is an act no text records"; # today's parser refuses the unknown key, so AC3 fails too here; on c0181's tree only AC5 would
row c0181-first-no-codify-line "AC3 AC5"
