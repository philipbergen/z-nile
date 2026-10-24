# Review 010: c0115 (design mode)
Inputs: prep-c0115 at c4d0a22e (delta `0170d63e..HEAD`: the §11 rebase 4e3fe69a, G12 65593fdb, G13 c4d0a22e); prototype `proto-c0115` at 59113b39 (its `rewrite-finished.luau` and `check.sh` are byte-identical to the prep's); a scratch clone of it with a simulated later main; `./zn lessons --when design --full`; `./zn capture c0115` ("no history for c0115 on origin/main": the item hasn't landed, so the capture isn't confirmed. The delta doesn't touch the title, Problem, Non-goals or Solution, and G12 and G13 delete only finished items' criteria, not c0115's own outcomes).
Round 9 had no findings, so none are dropped or repeated.

What holds:
- **Exactly six deletions.** The deletion commit 730dd246 removes six `check` statements and nothing else: R0025 RC2, c0010 AC7, c0045 AC6, c0067 AC11, c0068 AC7 and c0069 AC5 (49 lines, every one inside those statements). The rewrite commits before it are line-for-line substitutions: 33 files, 79 `-` and 79 `+`, with `+` equal to `-` in every file's numstat.
- **The three rules on today's tree.** Rule 1 (literal paths), rule 2 (nine loops) and rule 3 (c0035, c0058 and c0084: 19 paths) produce what the diff shows. `--check` is green on the prototype (`0 of 131`).
- **The layout changes.** `check.sh` runs from `z-nile/`, the scripts are anchored at `$ZN_ROOT`, the fixtures live in `pickman/.tracker`, and a missing registry is refused. I found nothing wrong with any of them.

### F1 [high] AC14's `rewrite-finished --check` compares against a tree frozen before the move, so later reviewed changes on main turn it red: c0120's AC18 flaw again
Where: `experiments/rewrite-finished.luau` (`premove()`, and the `--check` loop's `git show {pre}:{file}`); §8, "Finished `check.sh` files"; AC14; Implementation steps 5c and 10.
Evidence: in the scratch clone of the prototype at 59113b39, `main-sim` was branched from the move's parent (d6874ef2) and given two commits standing for later reviewed work on main:
1. a comment line added to `z-nile/.tracker/issues/done/c0004/check.sh`, a finished file c0115 never touches, and one added to `R0025/check.sh`;
2. a new item, `done/c0199/check.sh`, that reads `../.claude/skills/tracker/SKILL.md`.

What happened:
- **At the merge.** `git merge main-sim` into the c0115 branch was clean. `--check` then printed `c0004/check.sh: not its pre-move text rewritten`, `R0025/check.sh: not its pre-move text rewritten less RC2` and `1 … c0199/check.sh`, and exited 1. Running the rewrite and committing it fixes c0199, but c0004 and R0025 stay red. No script run fixes them, and editing them by hand is forbidden.
- **After landing.** With the branch squashed onto main, `--check` passes. One later comment in `done/c0007/check.sh` on main then turns it red again (`c0007/check.sh: not its pre-move text rewritten`, exit 1). `pre` stays pinned to the parent of the squash commit forever.
- **The three-way variant.** The same script with `pre = git merge-base HEAD main-sim` passes on the merged branch: `0 of 132`, exit 0.

Critique: AC14 judges main's own later work, not c0115's diff, which is exactly how c0120's AC18 broke. Main does write finished `check.sh` files during the window. c0114 already had to rewrite "the six check.sh files that finished on main since", and every future move's finished-file rewrite (the user's standing decision) edits them. The tempting fix is to say the freeze (AC12) prevents this. It doesn't: `busy` watches only the skill paths, not `*/done/*/check.sh`, and finished checks keep being judged after the landing.
Consequences: three-way against `git merge-base HEAD origin/main` brings in new states.
- An empty range (landed, or squashed): `DELETED`'s ids are already gone at the base, so `deleteCriteria` returns `RC2: 0 check statements` and goes red.
- No `origin/main`, or a shallow clone: must fail closed.
- A file at HEAD but not at the base (an item `./zn done` moves on the branch, c0115 and c0113 among them): it needs a rule of its own.
- An item finishing on main between merges arrives with old paths. Rerunning 5c fixes it, but step 10 reruns only step 5.
Recommendation: make `--check` three-way, as c0120 is doing.
- `base = git merge-base HEAD origin/main`; red when it fails or `origin/main` is missing.
- For every finished `check.sh` at HEAD whose path exists at `base`: HEAD must equal `rewrite(base text)` with `DELETED`'s statements removed. An id with no statement at `base` counts as already deleted only when HEAD has none either.
- A file not at `base` only has to need no rewrite.
- `HEAD == base` (an empty range) checks only that nothing needs rewriting, the same as AC13's G11.
- Drop `MARK` and `premove()`.

Add to steps 5 and 10: "rerun 5c (`rewrite-finished`, then `--check`) after every merge of `origin/main`, as its own commit".

Spec cases and mutants, run in a scratch clone:
- main edits a finished file after the move, merged: green;
- an item finished on main with an old path, merged: red until 5c reruns, then green;
- the branch deletes RC3 too: red;
- landed, then a later main edit: green;
- no `origin/main`: red.

Lesson: ticket-prep/design-the-execution-window

### F2 [high] c0040 AC1 and AC2 pass before the move and fail after it, no rule carries them, they aren't in `DELETED`, and AC14 is green
Where: `z-nile/.tracker/issues/done/c0040/check.sh:7-9`; §8 (three rules, "Six criteria no rule carries are deleted"); Verification log ("Every edited finished check (33 files) run by hand … no criterion is red on the prototype that is green on the base").
Evidence: c0040 sets `R="$(git -C "$(dirname "$A")" rev-parse --show-toplevel)/.claude/skills"`, then runs `grep -qi "reviewer.*opus" "$R/execute-raft/SKILL.md"` (AC1) and the same on `$R/ticket-prep/SKILL.md` (AC2).
- Rule 1 needs a literal `<up>.claude/skills/<old>`.
- Rule 3 needs an assignment of exactly `<up>.claude/skills`, and this one is `$(…)/.claude/skills`.

So c0040 isn't rewritten. In the clone, AC1's grep exits 2 on the prototype (the file is gone) and exits 0 on the base's `execute-raft/SKILL.md`; AC2 also exits 0 on the base. The by-hand run covered only the 33 edited files, so the claim that exactly six criteria break is unproven, and AC14 can't see this case: it only checks that the three rules were applied.
Critique: this is a finished criterion turned red by the move, which the user's decision says a rewrite must prevent, yet it is neither carried nor among the decided deletions. The tempting fix is to add c0040 to `DELETED`. That is a seventh deletion the user hasn't decided, and a rule can carry it.
Consequences: widening rule 3 (a variable whose assigned value ends in `/.claude/skills`, in any form) could also catch a variable that holds some other repository's path. On today's tree only c0040 matches, and the exact check pins the result. Any other uncarried form remains possible until something scans for it independently.
Recommendation: widen rule 3 to cover an assignment whose value ends `.claude/skills` (then `"`, a space or the end of the line). This falls under the user's standing decision ("a move that breaks a finished file's paths rewrites them"). If the author reads it as a new rule rather than G13's, it goes to the user as G14.

Then make AC14's script fail, independently of the rules, on any finished `check.sh` that still names `.claude/skills/<old>` or `/<old>/SKILL.md` for an old skill. A grep of the prototype finds c0040 as the only such file today.

Rerun the base-against-prototype comparison over every finished `check.sh` that names `.claude/skills` or an old skill name, not only the edited ones, and record it. Mutant: c0040 left as it is must be red.
Lesson: ticket-prep/new-rules-migrate-existing-work

### F3 [medium] The finished absence checks that run `grep -r` over `../.claude/skills` now pass without checking anything, because `grep -r` doesn't follow the new links
Where: `done/c0005/check.sh:54`, `c0046:41`, `c0067:63` (AC10), `c0070:42`, `c0071:30` (AC2) and `R0013:26`; §8, rule 1, which needs a `/<old>` after the folder.
Evidence: in the clone (z-nile/), `Cap: 3 rounds` was appended to `skills/zz-review/SKILL.md`. Then `grep -rnF 'Cap: 3 rounds' ../.claude/skills` exits 1 and finds nothing, while `grep -R` finds it. c0071 AC2's `bad=$(grep -rnF … ../.claude/skills || true); [ -z "$bad" ]` therefore passes whatever the skills say, and so do the five others like it. Before the move, `.claude/skills` held real folders and the scan worked.
Critique: none of these is red, so no by-hand run notices, but each has become a vacuous pass. The tempting fix is to change `-r` to `-R` in those files, which edits a flag rather than a path: something the rewrite decision doesn't cover.
Consequences: rewriting the operand to the real folders means one operand becomes two (`skills ../pickman/skills` from `z-nile/`). That is fine for `grep`, and the exact check then pins it.
Recommendation: add rule 1b. A bare `<up>.claude/skills` that ends the word (a space, a quote or the end of the line, never `/`) becomes the real skills folders from the home. It is the same path arithmetic as rule 1, and it carries all six. List them in §8's counts. Mutant: plant a banned phrase in `zz-review` and check that c0071 AC2 goes red after the rewrite.
Lesson: testing/no-vacuous-pass

### F4 [low] AC14 and two other places still describe G12's state
Where: AC14 ("R0025's RC2 deleted, G12, and nothing else"); §8's opening ("with two rules, nothing else", followed by three bullets); the script's header ("rewritten by the two rules").
Evidence: G13 deleted five more criteria and added a third rule; `DELETED` and §8's later paragraph say so.
Critique: an executor or code reviewer who reads AC14 literally sees five deletions it forbids.
Consequences: none.
Recommendation: AC14 should say "the six `DELETED` criteria (G12, G13) and nothing else", and both other places "three rules".
Lesson: ticket-prep/restated-rules-move-together

Verdict: changes
