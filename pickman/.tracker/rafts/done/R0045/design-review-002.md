# Review 002: R0045 (design mode)
Inputs: HEAD 327a6bba (origin/main c343f001, which changes neither narrowed file since R0011 #87) plus the uncommitted `tracker/rafts/R0045/` (R0045.md, check.sh, harvest.md, design-refute-001.md, experiments/narrowing.patch, experiments/mutants.py), `tracker/issues/c0128/` (c0128.md, check.sh, acceptance/titles, guards, golden), and the two new lessons under `.claude/skills/testing/lessons/`. Scratch trees `.worktree/proto-r45-main` (already held the revised patch and the current specs, left as found) and `.worktree/proto2-hiscores-top` (src equals R0044's `prototype.patch`, diff sha unchanged after the runs). `scripts/tracker.sh capture c0128` (2895f0c7, no marker).
Dropped from design-review-001: F1, F2, F3, F4, F5 (all fixed as claimed; see below).

Verified and fine:
- F1: `golden.spec` uses c0103's normalisation byte for byte and pins sha256 digests. On origin/main plus the patch, and on R0044's prototype plus the patch, the two narrowed files and the three c0128 specs pass (44 cases each). stylua `--check` and selene are clean. The only id-shaped tokens the mask hides are real item ids (c0128, d0124, f0024, f0026, f0061, f0065), so no code token can change under the mask.
- F2: the opens case now requires `companion|HiscoreEntries|all`, and the budget loop's text is pinned by the golden.
- F3: all three specs build their paths with `renamed.id` and split them in two parts.
- F4: `#names` is built from `w.stores` (one entry for each kind, name and scope), so a store opened under two kinds gives 7 or 8 and fails.
- F5: the prep note now says the capture conflicts with itself and that the Outcome wins.
- `mutants.py` kills 11 of 11 on the prototype. I reran it without `golden.spec`: titles and guards kill the 8 rows the table gives them, and exactly top-skips-budget-check, unnarrowed-case-loses-assert and comment-edit survive. So the table's attribution of those three rows to `golden` is accurate.
- `tracker.sh check c0128` on the unpatched branch: AC1 and AC2 pass, AC3 fails (5) and AC4 fails (2), as Implementation step 2 says. `promote-check R0045` is OK.
- Overrides: `scripts/affected` for the two files selects only themselves. The `grep` hits (f0024 `period`, c0106 `narrow-adapter`) name other adapter specs. No prepared or active item other than c0128 and d0124 names either file, and d0124 does not touch them.
- Scope: the title, Problem and Solution are as captured. The prep only adds detail and the conflict note. Every outcome has a Checked criterion (AC1 to AC4).

### F1 [medium] Implementation step 1's fallback ("if a hunk does not apply, follow the Design above") can no longer pass: the golden pins prep's base, not the Design
Where: c0128 Implementation steps 1–2; `golden.spec.luau` (the digests "of the narrowing in narrowing.patch applied to origin/main")
Evidence: the digests are of `aa100297` and `21647d7e` (the patch's `index` pre-images) with the patch applied. If any raft changes either file between this prep and R0045's execution, the hunk may not apply (or may apply with fuzz). Even a narrowing hand-written perfectly from the Design then has a different normalised text, so AC4 is red. The executor may not edit the sequestered golden (execute-raft, sequestration), so the documented fallback leads straight into a check it cannot pass. Today the risk is low: no prepared item names the files, and main last changed them in R0011.
Critique: the tempting fix is to delete the fallback sentence. That leaves the executor guessing what to do when the base moved.
Consequences: the execute-raft stop conditions already cover a sequestered check that cannot pass. The fix only has to send the executor there before any work. Two states are hard to tell apart: the patch applying with an offset to a changed file is the same failure in disguise. Checking the pre-image blobs catches both.
Recommendation: replace step 1's fallback with "First check that `git rev-parse origin/main:tests/acceptance/f0024/adapter.spec.luau` and `…f0026/adapters.spec.luau` start with `aa100297` and `21647d7e` (the patch's `index` lines). If either differs, or the patch does not apply, `main` has changed a file since prep and AC4's digests no longer describe it: stop (execute-raft stop conditions) and have c0128 re-prepped (the patch rebased and the digests recomputed)". Say the same once in the Design's golden bullet ("the digests bind the narrowing to these two pre-image blobs").

### F2 [low] Three places still describe the checks before the golden
Where: R0045.md Exit criteria ("c0128's AC1–AC3"); c0128 Maintainability ("The c0128 specs pin the case titles and the guards, so a later edit cannot narrow by deleting"); c0128 Usability ("the failures still name what broke (the store, the count, the compared values)")
Evidence: AC4 now exists and RC0 runs it. The golden is now the main pin against a later edit. A golden failure prints two digests and nothing about where the file changed.
Critique: these are stale restatements (ticket-prep lesson "Restated rules move together"). The Usability claim is false for AC4.
Consequences: none.
Recommendation: make the Exit criteria say AC1–AC4, and name the golden in Maintainability. In Usability, and in the golden spec's header, say that a digest failure is located by diffing the file against the commit that landed c0128 (`titles` and `guards` name the case when one of theirs is involved), and that the spec's "got" value is the new digest to record when a chore changes the file on purpose.
Lesson: ticket-prep/restated-rules-move-together

Candidate lessons (for the lead):
- testing/narrowing-pins-the-whole-file (a note on the lesson just added): a whole-file pin taken in prep binds the executor to prep's base. The Implementation steps must check the pre-image and stop when it moved, not "follow the Design". Check: "If `main` changes the pinned file before execution, what does the executor do, and can AC still pass without editing the sequestered pin?"

Verdict: changes
