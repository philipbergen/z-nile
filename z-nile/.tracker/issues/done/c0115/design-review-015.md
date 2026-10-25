# Review 015: c0115 (design mode)
Inputs: prep-c0115 at 97d58ade (`git diff 39cbeaac 97d58ade -- z-nile/.tracker/issues/c0115 .claude/skills`: freeze.spec, c0115.md, harvest.md, the lesson `history-tests-survive-squash`); impl-c0115 at 899762f0 (`git diff ca212954 899762f0 -- z-nile/engine z-nile/skills`: `c0115Move`, `allInside`, the comments, the lesson); design-review-014.md and design-refute-014.md. Every experiment ran in a scratch clone (`scratchpad/review015/work`) whose origin is a bare copy (`origin.git`) holding the real remote's branches as `git ls-remote origin` lists them today, with `impl-c0115` = 899762f0 and `prep-c0115` = 97d58ade. Nothing was pushed to the real remote.
Dropped from design-review-014: F1, F2, F3, F4, F5 (fixed as the refute says; F3 carries the user's 2026-10-25 decision, "Delete merged only").

What holds:
- **Spec run.** `lune run tests/run -- .tracker/issues/c0115/acceptance/freeze.spec.luau` (from `z-nile/`) gives 7 passed, 0 failed.
- **The author's mutants, spot-run** (`mut.sh`, one at a time, reverted):
  - G (the oldest commit of the range) and H (the tip): killed, 4 cases red each;
  - I (the whole history), J (the first of several), "the last of several": killed by the new case;
  - K (no `/` boundary) and M (`..` allowed): killed by the scope case.
- **014 F1's shape is in the fixture now.** `impl-c0115` sits on `base-work`, which main took as a squash. `below-the-move` blocks, and `at-the-move` (below the tip) is ignored.
- **014 F2.** The lookup reads `refs/remotes/origin/main..refs/remotes/origin/impl-c0115`, matches `%s` by plain prefix, and returns nil for zero or two matches, which fails closed. On today's remote the range holds 277 commits and exactly one matches (6ae30bb2).
- **`allInside`.** `..` is refused by whole segment (`/{n}/` holds `/../`, plain find). Absolute paths and `././x` fall outside, which turns the freeze off: the safe direction.
- **AC12 today** (scratch clone): `./zn busy .claude/skills z-nile/skills pickman/skills` blocks only on `origin/impl-c0120`. `proto-c0115` is gone from origin but is still a local branch in the real checkout, and busy reads `refs/heads` too, so step 1's text about it still holds. This is the accepted state (014 F3).
- **Harvest** covers 014 F1 to F5. The lesson's new "How to apply" is a real lesson, not a restated finding. F2's search question is missing from its `check:` (F3 below).
- `./zn lessons --when design --full`: I asked every `check` of the changed parts. Only the findings below came out of that.

### F1 [low] Two plausible mutants of `c0115Move` survive freeze.spec, and one of them reopens a rogue exemption through a local branch named `origin/impl-c0115`
Where: `c0115Move` in `z-nile/engine/main.luau`; freeze.spec's move-commit case; the G14 Rules and mutants row.
Evidence:
- **U, short refnames** (`"origin/main..origin/impl-c0115"` in place of the `refs/remotes/…` names): `7 passed, 0 failed`. Git resolves `refs/heads/origin/impl-c0115` before `refs/remotes/origin/impl-c0115`. In the scratch clone I ran `git update-ref refs/heads/origin/impl-c0115 <a commit on origin/main with subject "c0115: move the skills (fake)">` and cut `rogue` from it, adding `z-nile/skills/zz-rogue/SKILL.md`. Then `./zn busy .claude/skills z-nile/skills pickman/skills` gives:
  - under U: `ignored for c0115's freeze: rogue (holds its move)`;
  - unmutated: `branch rogue changes …`.
- **T, the subject contains the text** (plain find) instead of starting with it: `7 passed`. This one is close to equivalent: it only adds matches, and a second match pins nothing.

Critique: the code is right today. But the spec already has a "local `origin/…` branch" case (c0120 code review 011 F5) for names, and not for the ref this lookup reads, so a refactor to short names goes unnoticed. This is low because it needs both a rewrite of correct code and a local ref in the user's own repository.
Consequences: none beyond one more fixture branch. The spec must delete it afterwards, since later cases reuse the fixture.
Recommendation:
- In the move-commit case, add a local branch `origin/impl-c0115` that holds one commit with the subject `c0115: move the skills (fake)`, and a branch cut from it that edits a skill path. Assert that the branch blocks and that `on-the-impl` is still `holds its move`.
- Add U to the G14 row as killed.
- List T as equivalent, or kill it with a range commit whose subject quotes the text mid-line (`Revert "c0115: move the skills …"`), which must leave the pin unchanged.

### F2 [low] AC13 still finds the move commit with `--grep='^c0115: move the skills'`, the body-line match that 014 F2 removed from the engine and that the new lesson forbids
Where: `check.sh` `moves_only` (`moves=$(git log --format=%H --grep='^c0115: move the skills' "$base..HEAD")`). The same section's comment and AC13's text both say "exactly one commit whose subject starts". G14 calls this "the range AC13 reads" as if the two rules were the same.
Evidence:
- `^` anchors every message line, so a commit of the branch's own range whose body has a line starting `c0115: move the skills` counts as a second move commit, and AC13 goes red ("want one moves commit").
- The branch's own range includes every prep commit merged into impl-c0115, and those prep messages quote item subjects routinely.
- Today the range holds one match only (`git log --grep='c0115: move the skills' origin/main..impl-c0115` lists only 6ae30bb2), so the hole is latent.
- The engine and AC13 now disagree on what "the move commit" is. The lesson's "How to apply" says "never `--grep`, which also matches body lines".

Critique: this fails closed, so it is low. But check.sh is sequestered: at execution time a false red can't be fixed by the executor and becomes an escalation. The draft also repeats the defect its own new lesson names.
Consequences: AC13 stays stricter than the engine (zero or two matches is red in both). The change is only which field is read.
Recommendation: in prep, change `moves_only` to read `git log --format='%H %s' "$base..HEAD"` and keep the lines whose subject starts with the plain text `c0115: move the skills` (for example `awk` with `index($0, " c0115: move the skills") == 41`, or `cut -d' ' -f2-` and a fixed-string prefix test). Rerun M44/M45, and add a mutant row: a branch commit whose body line starts with the subject text leaves AC13 green.
Lesson: zz-arch/history-tests-survive-squash

### F3 [low] The updated lesson's `check:` still asks only about the history test, so the range, subject and exactly-one rule F2 added to it is invisible to `--when design` readers
Where: `.claude/skills/architecture/lessons/history-tests-survive-squash.md`, frontmatter `check:`.
Evidence: the check is "Does any rule decide by 'a commit of branch X that main doesn't have'? … Is there a spec case where main squashes the base?". The body's new half ("a commit found by a search is only as unique as the range searched … subject line only … exactly one") has no question. Reviewers run the `check` lines (review skill, design item 10). That is how F2 above could slip through on this round's own draft.
Critique: a lesson whose check misses half its rule teaches only by `--full` reading.
Consequences: none.
Recommendation: append to the check: "When a commit is found by a search, does the lookup read the same range and the same field (the subject) as the rule that claims it unique, and refuse zero or two matches?"

Candidate lesson (for the lead): when one rule is fixed in the engine, grep for the same mechanism in the item's own sequestered files before the refute. Here the engine moved off `--grep` and AC13 kept it. Check: "Does every other place that finds the same thing (check.sh, experiments, specs) use the same lookup as the one I just fixed?" (`git grep -n -- "--grep=" -- 'z-nile/.tracker/issues/c0115' z-nile/engine` finds AC13's line). This may fit as a note on zz-design/restated-rules-move-together.

Verdict: approve
