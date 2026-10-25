# Review 002: R0003 (code mode)
Inputs: `git diff main...HEAD` at 9bc2980 (tracker start commit d298976); review-001.md and refute-001.md; R0003 raft doc and check.sh; c0010 issue doc and check.sh; promoted acceptance specs in tests/acceptance/c0010; architecture, testing and tracker skills. I ran `scripts/check.sh --full` (GATE PASSED, 113 passed, 18 spec files), `scripts/tracker.sh check c0010` (AC1-AC7 PASS, 7/7) and `scripts/tracker.sh check R0003` (5/5). `git diff -M d298976 -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' 'tests/acceptance/**'` shows only 100%-similarity renames (active to done, and the promotion to tests/acceptance/c0010 by `tracker.sh done`), so sequestration holds. `git status` was clean after all runs.
Dropped from review-001: F2 (the design scopes failure reporting to expectations, never-reached expectations and errors raised by `step`; other errors propagating plainly is as designed), F6 (process record only; no code impact). F1, F3, F4 and F5 are fixed in 038a433: `validate` rejects names outside `^[%w_-]+$` before `model.new` runs (the trailing `-` in the set is literal), `assertDeterministic` buckets events by tick once per run and compares every tick 0..max(#states)-1, the skill example requires `t`, and the scenario spec comment points to the acceptance specs for leak detection.

### F1 [low] Misplaced backtick in the testing skill's tier guidance
Where: .claude/skills/testing/SKILL.md, Simulations, "Choosing a tier"
Evidence: the text reads "`tests/integration/ is for` cross-feature checks that don't step time", so "is for" renders as code and the directory name does not stand alone. It reads as a typo in the rule that tells authors which tier to use.
Fix: change it to "`tests/integration/` is for cross-feature checks that don't step time".

## Judged criteria (code mode only)
None defined for c0010 or R0003.

Verdict: approve
