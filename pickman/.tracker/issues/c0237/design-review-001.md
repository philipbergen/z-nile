# Review 001: c0237 (design mode)
Inputs: worktree prep-lobby-tooling-pattern at 2d7f4e2b plus uncommitted c0237.md, check.sh, harvest.md and z-nile/skills/zz-rules/lessons/a-tracked-fix-lands-through-its-raft.md; fix commit 51968dcc (#230); `./zn capture c0237` (05bee6b8); `./zn check c0237` (3/3 PASS); AC2/AC3 commands run against scratch copies of the spec (unchanged, `%{` put back, line 55 deleted, file missing).

Checked and sound:
- Scope: the title and Problem match the capture word for word. The Solution adds detail and a `Decided with the user (2026-11-04)` line. The one outcome (the escape is gone, so luau-lsp stops failing) has a Design and Checked criteria. Nothing was dropped.
- Honesty: the Design, the Solution and Implementation step 2 all say the code change is already on `main` (51968dcc touches the spec's line 55) and that the raft makes no edit. Step 1 stops if AC3 fails because the line moved.
- AC3 is sound. It is a fixed-string count that must equal 1. Its results: unchanged spec, pass; `%{` re-added, fail; line deleted, fail; file missing, fail (`grep -c` prints nothing, and `"" == 1` is false). It cannot pass by finding nothing. Because the count must be exactly 1, it also kills a duplicated line.
- AC1: the spec runs `t.expect(each).toBe(true)` on line 62, so a pattern that matches nothing turns it red, as the Rules row says.
- Repository safety: all three checks are reads, or a spec run through `tests/run`. Overrides names the one promoted spec, which #230 already applied.

### F1 [low] AC2 passes by finding nothing when the spec file is absent
Where: check.sh AC2
Evidence: `! grep -nF -e "%{" -e "%}" <missing file>`: grep exits 2, and `!` turns that into success. In the scratch run, the "missing" case gives AC2=pass.
Critique: On its own, AC2 cannot tell "checked and clean" from "nothing to check". AC1 and AC3 both fail when the file is missing, so the issue as a whole stays safe. That is why this is low.
Consequences: none, if fixed as below.
Recommendation: make AC2 require the file, e.g. `bash -c 'f=tests/acceptance/f0061/lobby-tooling.spec.luau; [[ -f $f ]] && ! grep -nF -e "%{" -e "%}" "$f"'`. Or leave it as it is and add a sentence to the Rules and mutants row saying that AC1 and AC3 cover the missing-file case.
Lesson: zz-test/no-vacuous-pass

### F2 [low] The Unknowns record is stale after AC3 was added
Where: c0237.md, Unknowns & experiments: "`./zn check c0237` passes AC1 and AC2 on `main`"
Evidence: this prep adds AC3 to check.sh (see `git diff HEAD -- check.sh`), and `./zn check c0237` now runs and passes three criteria.
Critique: the record no longer describes what was checked.
Consequences: none.
Recommendation: change the record to "passes AC1–AC3".

### F3 [low] The type-stage outcome is shown only by proxy
Where: c0237.md, Usability ("The pickman type stage and the stop hook pass on `main` again") and AC2
Evidence: the Problem's failure is luau-lsp's FormatString diagnostic. AC2 greps for the two escapes that caused it. No criterion runs luau-lsp on the file.
Critique: the proxy is a fair one. It is exactly the rejected token, and the gate's type stage runs at the merge, which the Regression guard names. Still, the Usability sentence claims an observed result without saying where it comes from.
Consequences: none.
Recommendation: point the Usability sentence at its evidence (for example, the `main` gate run after #230, or the raft's `--full` gate). No new check is needed.

Lessons: `./zn lessons --when design` checked. zz-test/narrowing-pins-the-whole-file does not apply, because the chore respells one pattern and does not narrow the spec. The harvested lesson zz-rules/a-tracked-fix-lands-through-its-raft is a genuine `build` lesson that another raft could fail, not a restated finding.

Verdict: approve
