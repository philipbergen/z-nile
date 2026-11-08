#!/usr/bin/env bash
# Acceptance checks for c0247. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0247 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0247"

check "AC1: z-ticket restates the request (title, outcome, who, non-goals, Solution ideas, type, project, overlaps) before anything is created and creates nothing until the user approves" lune run tests/run -- "$A/docs.spec.luau"
check "AC2: a dispatched run asks first and exclusively; otherwise plan mode where EnterPlanMode is offered or deferred, and printing or a subagent's return to its lead, in that order" lune run tests/run -- "$A/docs.spec.luau"
check "AC3: one restatement per message, no added design or scope, and only a ticket made from the agent's own finding is filed at once" lune run tests/run -- "$A/docs.spec.luau"
check "AC4: the paragraph appears once, before the first numbered step, and step 0 waits for the confirmation" lune run tests/run -- "$A/docs.spec.luau"
check "AC5: the README's table and flow name the confirmation" lune run tests/run -- "$A/docs.spec.luau"
# the whole block from the title through step 0 is exactly the Design's: the paragraph, and step 0 as the merge
# base's with its one phrase added (design review 004 F1, 005 F1). A line next to the paragraph joins its Markdown
# paragraph, so one physical line is not enough to pin. Sequestered: a later issue that rewords the paragraph carries
# its own copy of this pin in its own check.sh. A contradiction elsewhere in the file (step 2, the Headless section)
# is not pinned, because a whole-file pin turns red on a raft mate's edit: code review judges it
export PARA
read -r -d '' PARA <<'EOF' || true
**Confirm intent first.** When the ticket carries words of the user's (a request, a correction, a problem they point out), restate it before anything is created (no worktree, no `./zn new`): the title, the outcome, who is affected, the non-goals, the Solution ideas, the type (feature, defect or chore) and the project, as you would write them into the Problem, with any overlap `./zn list backlog` shows. The user approves or corrects it, and the stub is made from the approved version. A correction means you restate again. Under `./zn dispatch` (`ZN_DISPATCH=1`), on any CLI, never use plan mode and never only print: ask it the way the dispatcher's prompt tells you to ask the user a question, and stop. Otherwise, in Claude Code, when `EnterPlanMode` is offered (or listed as a deferred tool: load it with ToolSearch) and you are not already in plan mode, call it, write the restatement to the plan file, ending with the line `Next: capture with the z-ticket skill, steps 0 to 6; build nothing.`, and call `ExitPlanMode`: the user's approval is the go-ahead, and a rejection means you ask what to change and restate. Without it, or if the user declines plan mode, or if you are already in plan mode (leave its plan alone), print the restatement and stop until the user answers; a subagent returns the restatement to its lead, which confirms it with the user. A message with several tickets gets one restatement covering all of them, one block per ticket. The restatement adds no design and no scope: it is the user's words, sharpened. A restatement the user has already approved counts, whether they gave it in this conversation or it comes in your brief or in the reply `./zn dispatch retry` hands over. A ticket made only from your own finding (a review finding, a failed step, a graph miss you found) has no words of the user's to check and is filed at once.
EOF
block_exact() {
  local doc=$ZN_ROOT/z-nile/skills/z-ticket/SKILL.md base old0 want got
  base=$(git -C "$ZN_ROOT" merge-base HEAD origin/main) || { echo "no merge base with origin/main"; return 1; }
  # step 0 is the merge base's, with the one phrase added (a raft mate's edit to it is not blocked)
  old0=$(git -C "$ZN_ROOT" show "$base:z-nile/skills/z-ticket/SKILL.md" | grep -m1 '^0\. ') || return 1
  [[ $old0 == *', before anything is created:'* ]] || { echo "the base's step 0 no longer has the phrase the Design edits"; return 1; }
  want=$'\n# Make an issue\n\n'"$PARA"$'\n\n'"${old0/, before anything is created:/, after the confirmation above and before anything is created:}"
  # from the line after the frontmatter's closing --- through step 0's line
  got=$(awk 'n==2{print} /^---$/{n++} /^0\. /&&n==2{exit}' "$doc")
  [[ $got == "$want" ]] || { echo "the text from the title through step 0 is not the Design's"; diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") | head -5; return 1; }
}
# nothing is renumbered: the numbered step headings (number and bold label) equal the merge base's (design review 001 F6)
steps_keep_numbers() {
  local base cur old new
  base=$(git -C "$ZN_ROOT" merge-base HEAD origin/main) || { echo "no merge base with origin/main"; return 1; }
  old=$(git -C "$ZN_ROOT" show "$base:z-nile/skills/z-ticket/SKILL.md" | grep -oE '^[0-9]\. \*\*[^*]+\*\*') || return 1
  new=$(grep -oE '^[0-9]\. \*\*[^*]+\*\*' "$ZN_ROOT/z-nile/skills/z-ticket/SKILL.md") || return 1
  [[ -n $old && $old == "$new" ]] || { printf 'step headings changed\n--- base\n%s\n--- now\n%s\n' "$old" "$new"; return 1; }
}
check "AC6: z-ticket's numbered steps keep their numbers and labels (promoted specs and c0135 refer to 'step 5')" bash -c "$(declare -f steps_keep_numbers); ZN_ROOT='$ZN_ROOT'; steps_keep_numbers"
# the promoted specs that read the two edited files, by name (SKILL.md, README.md) or by scanning every skill, still pass
# (Overrides: none). A raft mate's Override or this issue's own promotion cannot turn it red, unlike a diff of
# tests/acceptance (design review 001 F2); the list is found by reading the specs, so a corpus scanner is included
# (design review 002 F3). 46 specs, about 2.5 minutes.
check "AC7: the promoted z-nile specs that name SKILL.md or README.md still pass" bash -c "cd '$ZN_ROOT/z-nile' && specs=\$(git grep -lE 'SKILL\\.md|README\\.md' -- tests/acceptance | grep '\\.spec\\.luau\$' | grep -v '/c0247/') && [[ -n \$specs ]] && lune run tests/run -- \$specs"

check "AC8: the text from the title through step 0 is byte for byte the Design's (the paragraph, and step 0 as the merge base's with the phrase added)" bash -c "$(declare -f block_exact); ZN_ROOT='$ZN_ROOT'; block_exact"

finish
