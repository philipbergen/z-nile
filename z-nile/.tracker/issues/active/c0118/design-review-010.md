# Review 010: c0118 (design mode)
Inputs: prep-c0118 19467def (a focused recheck of the rewritten Implementation step 1 only: `git diff 195858d8 19467def` touches c0118.md, 5 + / 4 −); impl-c0118 97c35b43; impl-c0117 (local 626bce81, origin 434d94e1, PR #125); origin/main 1e749844; lesson `z-design/watch-steps-name-their-base` as on prep-c0121 13536dae. Scratch clone `dr-c0121-005/c18` (under the reviewer's scratchpad): origin/main, with 434d94e1 merged to stand in for c0117's landing and prep-c0118 merged to stand in for this prep's.
Scope: step 1 only. The rest of the design was approved at round 009 and is not re-reviewed.

What holds, and was checked:
- **The watch, today.** All 13 watched paths exist on origin/main. `git log --first-parent --format='%h %s' 6684f411..origin/main -- <the 13 paths>` prints exactly one commit, `30196933 R0050: Split rafting out of design (#121)` (c0116's landing, allowed). The older `660ccae1 R0050: Game alias requires (#6)` is before 6684f411 and outside the range, as the step says. With the base at 6684f411, the method finds c0116's landing and would stop on anything else that touched a watched path, so it does catch an unexpected upstream change, as long as the base stays there (F1).
- **The apply, mechanically.** In `c18`, `git diff 434d94e1 impl-c0118 -- . ':!*/.tracker/**' | git apply -3` applies the engine, README, zz-rules, cachepaths and overridden-spec hunks cleanly. The six lessons whose text equals the prep's merge to no change. Only the three paths in F2 conflict.

### F1 [medium] The base moves past the landings it is searched for: after "that rebase's merge-base", c0116's and c0117's landings are outside `<base>..origin/main`, so "zero matching commits for a done item stops the step" always fires, and the window before the rebase is judged by nobody
Where: step 1, **Commits** ("`<base>` is 6684f411 (the prep base) until this prep is rebased onto `main` after c0117 lands, and that rebase's merge-base after it … Only commits in the range count … Zero matching commits for a done item stops the step")
Evidence:
- The step's own order: c0117 lands, then this prep is rebased onto main, which makes its merge-base a commit at or after R0052's landing. c0116's landing (30196933) is older still.
- Run on today's history, with a base taken after the landing as the rebase would take it:
  ```
  $ git merge-base --is-ancestor 30196933 origin/main && echo "R0050 #121 is an ancestor of origin/main"
  R0050 #121 is an ancestor of origin/main
  $ B=$(git rev-parse --short origin/main)
  $ git log --first-parent --format='%h %s' $B..origin/main | grep -cE '^[0-9a-f]+ R0050: .*\(#[0-9]+\)$'
  0
  ```
  An executor finds `./zn find c0116` under `done/` (R0050) and no `R0050:` commit in the range, so it stops for a re-prep on a sound branch. The text's own "Only commits in the range count" closes the reading that would let it look further back.
- Commits between 6684f411 and the new base are judged only by "a rerun of this search" that the rebase records. No rule says what the rebaser does with a non-landing commit, and no review sees it. So an unexpected upstream change in that window passes.
Critique: the base does two jobs, "the world the carried diff was made on" and "where the dependencies' landings start", and both lie before the rebase. Dropping the zero rule is tempting, but then a done dependency whose landing can't be found passes silently (`zz-arch/history-tests-survive-squash`). The same defect is in c0121's step 1 (c0121 design review 005 F1), whose wording this step copied.
Consequences:
- With the base pinned at 6684f411, the range always holds c0116's and c0117's landings, and the zero rule is sound.
- The range grows, so any other item's commit on a watched path stops the step. That is the intended cost.
- The rebase then chooses nothing. It records a rerun, and a non-landing commit it finds is a re-prep then.
Recommendation:
- Strike "and that rebase's merge-base after it". `<base>` is 6684f411, always.
- The rebase reruns the search from 6684f411, records the output in the Verification log, and stops for a re-prep on any commit that isn't allowed.
- Correct the note in `z-design/watch-steps-name-their-base` the same way (with c0121).
Lesson: z-design/watch-steps-name-their-base; zz-arch/history-tests-survive-squash

### F2 [medium] The carried diff includes `z-nile/next` (the id counter) and eight lesson files the prep lands itself; three of them conflict outside c0118's allowed hunks, so step 1 stops, and "re-applying c0118's change" to `next` would rewind the counter
Where: step 1, **Apply** (`-- . ':!*/.tracker/**'`; "A conflict in any other hunk stops the step")
Evidence:
- `git diff --stat 434d94e1 impl-c0118 -- . ':!*/.tracker/**'` lists 24 files, including `z-nile/next` and eight `z-nile/skills/*/lessons/*.md`. The diff on `next` is `issue 152 …` → `issue 153 …`. origin/main has `issue 159 jolly-copper-crimson / raft 54`.
- Run in `c18` (main + 434d94e1 + prep-c0118 merged):
  ```
  Applied patch to 'z-nile/next' with conflicts.
  Applied patch to 'z-nile/skills/z-design/lessons/never-narrow-captured-scope.md' with conflicts.
  Applied patch to 'z-nile/skills/z-design/lessons/restated-rules-move-together.md' with conflicts.
  U z-nile/next   (ours: issue 159 / raft 54; theirs: issue 153 / raft 53)
  ```
- None of the three is in the step's list of c0118's own hunks, so the step stops on a sound branch. An executor who reads `next` as "c0118's change" and keeps theirs sets the counter back to 153, and the next `./zn new` reuses an id main has already issued.
- The two lessons conflict because prep-c0118 and impl-c0118 hold different texts of them (`git diff --quiet impl-c0118 prep-c0118 -- <file>` differs for both). They ride in the prep PR.
Critique: the counter is the "file main writes during the execution window" from `z-design/design-the-execution-window`. The tempting fix is to add `next` and the lessons to the allowed list "keeping upstream". That works, but it makes the executor judge files that were never c0118's change.
Recommendation:
- Carry only c0118's change: replace `.` with the Touched modules and the Overrides-line specs (the 13 watched paths, plus `z-nile/engine/boardview.luau` and `z-nile/tests/tooling/board.spec.luau`, which the diff also changes).
- Say that `z-nile/next` and lessons are never carried: lessons land with the prep, and the counter is main's.
- Check with a run: on main + c0117, the narrowed diff applies with no conflict outside the listed hunks.
Lesson: z-design/design-the-execution-window

### F3 [medium] `git merge-base impl-c0117 impl-c0118` names a branch that is gone by the time the step can run: impl-c0117 is R0052's PR branch, deleted on merge
Where: step 1, **Apply** (`git diff $(git merge-base impl-c0117 impl-c0118) impl-c0118 …`); the precondition "after c0117 is done"
Evidence:
- `gh pr list --state all --head impl-c0117` → #125 "R0052: Models and dispatcher (c0117)", open. `gh repo view --json deleteBranchOnMerge` → `true`. zz-rules' landing step 4 then runs `git -C <root> branch -D <branch>` on the local branch.
- So after c0117 is done, neither `impl-c0117` nor `origin/impl-c0117` exists. Run in `c18` with both refs deleted:
  ```
  fatal: Not a valid object name impl-c0117
  error: z-nile/engine/boardview.luau: does not exist in index
  pipe exit=1
  changed: 0
  ```
- It fails loudly and applies nothing, but the command as written can't run, so an executor who never saw this repo has to guess. The text does give "today the merge-base is 434d94e1", and 434d94e1 is an ancestor of impl-c0118, so it stays reachable.
Recommendation:
- Write the diff as `git diff 434d94e1 impl-c0118 -- <paths>`.
- Say that #122 is closed without deleting `impl-c0118`, and only after the apply is committed. A missing `impl-c0118` is fetched from `refs/pull/122/head`.
- Add to the `watch-steps-name-their-base` note: a carried diff's ends are pinned shas, or refs that outlive the step.
Lesson: z-design/instructions-runnable-where-they-run; z-design/watch-steps-name-their-base

Verdict: changes
