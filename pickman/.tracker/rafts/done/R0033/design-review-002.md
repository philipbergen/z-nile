# Review 002: R0033 (design mode)
Inputs: prep worktree `prep-narrow-play-again-specs` (HEAD plus uncommitted `tracker/rafts/R0033/{R0033.md,check.sh}`, `tracker/issues/c0063/{c0063.md,check.sh,acceptance/narrowed.spec.luau,experiments/narrowing.patch}`, `tracker/issues/done/f0031/{check.sh,f0031.md}`); `design-review-001.md`, `design-refute-001.md`; R0034's `experiments/{prototype.patch,c0063-narrowing.patch}` in `prep-game-over-to-lobby`.
Dropped from review-001: F1, F2, F3, F4 (each fix holds; evidence below).

Spot runs, in a `--no-hardlinks` clone under the scratchpad with the prep's diff and untracked dirs copied in (no tripwire, no `REPOSITORY CHANGED`):
- Unpatched: `narrowed.spec` 1 passed, 5 failed, all on the case/count tables (wiring right).
- With `narrowing.patch`: `stylua --check tests/acceptance/f0031` clean; `narrowed.spec` plus the four f0031 specs 34 passed; `bash tracker/issues/c0063/check.sh` 2/2; relabelled `tracker/issues/done/f0031/check.sh` 5/5; `tracker.sh promote-check R0033` OK.
- R0034 `prototype.patch` (which no longer carries f0031 edits) plus `narrowing.patch`: `narrowed.spec`, the four f0031 specs and `c0003/scripts.spec` 37 passed. Without the narrowing the same set fails 22, so the narrowing is still required and sufficient for those files. R0034's `c0063-narrowing.patch` is identical to c0063's `narrowing.patch` apart from index lines.
- Review-001 F1 re-checked: the gutted presentation-run case 2 now fails `narrowed.spec`; a count-preserving swap (`t.expect(true).toBe(true)` in place of one assertion) still passes, as E3 records and leaves to review. Since execution is `git apply` of a reviewed patch, I accept that.
- F2: nothing in `tests/` or `scripts/` reads f0031's check.sh labels (grep for the old label text finds only a comment in f0031's own overlay spec), and `narrowed.spec` checks only the `"$A/<name>.spec.luau"` arguments, so the relabel can't turn anything red. The f0031.md note is dated and leaves the historical ACs intact.
- Repository safety: `narrowed.spec` only reads files; c0063's and f0031's `check.sh` run only `lune run tests/run` and `tracker.sh find`; R0033's RC1 runs read-only `git merge-base`/`git diff`. No write path to the repository.
- Override check: `grep -rn f0031 tests/acceptance` outside f0031 finds only c0001/c0042 fixtures that use the id as sample data, and they don't read f0031's specs or check.sh. The Overrides line names all four specs.

### F1 [low] R0033's Experiments table still says E3 kills "the 10 mutants"; c0063 records 13
Where: `tracker/rafts/R0033/R0033.md`, Experiments phase table, row E3
Evidence: the row reads "`narrowed.spec` kills the 10 mutants | all killed", while c0063's Unknowns & experiments E3 lists 13 mutants ("All 13 killed"), including the three added for review-001 F1.
Critique: an executor reading the raft alone gets a stale count, and the per-case `t.expect(` count rule added after review-001 isn't mentioned at raft level.
Consequences: none.
Recommendation: change the row to "kills the 13 mutants (names, per-case assertion counts, narrowed needles)".

Verdict: approve
