# Review 001: R0003 (code mode)
Inputs: `git diff main...HEAD` at 2d683b2 (tracker start commit d298976); R0003 raft doc and check.sh; c0010 issue doc, check.sh and acceptance specs; architecture, testing and tracker skills. I ran `scripts/check.sh --full` (GATE PASSED, 64 passed, 12 spec files) and `scripts/tracker.sh check c0010` (AC1-AC7 PASS, 7/7). `git diff d298976 -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` is empty, so sequestration holds. `git status` was clean after both runs. Nothing in `src/` or `tracker/architecture.md` changed, and the new files are `--!strict` with legal requires (`@lune/*`, `@tests/*` only).

### F1 [low] Model `name` is not validated, although the design says `[%w_-]+`
Where: tests/lib/sim.luau:102 (`validate`) and :150 (replay path)
Evidence: the design declares `name` as `[%w_-]+` because it becomes a file name. `validate` never checks it. A model named `"../x"` makes `fail` build `.cache/sim/../x-seed1-tick3.json` and write outside the replay directory. A name with `/` fails inside the `pcall` and gives `replay: not written`, which hides the real cause. The impact is small (test-only, author-controlled).
Fix: in `validate`, or at the start of `execute`, reject a `name` that doesn't match `^[%w_%-]+$` before any step runs.

### F2 [low] Errors from `model.new`, `observe` and `stopWhen` bypass failure reporting
Where: tests/lib/sim.luau:208, :252, :259
Evidence: only `step` is wrapped in `pcall`. If `observe` or `stopWhen` raises at tick 40, the caller gets a raw Luau error with no model, seed or tick and no replay. Likewise, a table expectation against a non-table observation (`obs[k]` at line 194) raises an index error, not a `sim[...]` failure. The design scopes failures to expectations and `step` errors, so this is not a deviation. It is a debuggability gap that will matter once `observe` is a real Session summary.
Fix: wrap `observe` and `stopWhen` in the same failure path (kind `"step"`), or record the limitation in the testing skill.

### F3 [low] `assertDeterministic` is O(ticks x events)
Where: tests/lib/sim.luau:357-375
Evidence: `eventsAt` rescans the whole event list for every tick. A 1,800-tick run with about 10,000 events (a ghost-heavy scenario) does about 18M event visits, twice. That is harmless at today's sizes and would be slow across the 20-seed proxies the docs recommend.
Fix: walk both event lists once with an index cursor per run (events are stored in non-decreasing tick order).

### F4 [low] Testing-skill example uses `t` without requiring it
Where: .claude/skills/testing/SKILL.md, Simulations example
Evidence: the snippet requires `sim` and `Walker`, then calls `t.expect(...)`. Copied into a spec as written, it fails with `t` undefined. `t` is only in scope if the reader already knows to require `@tests/lib/t`.
Fix: add `local t = require("@tests/lib/t")` to the snippet.

### F5 [low] Scenario spec's determinism case cannot fail
Where: tests/scenario/harness.spec.luau ("is deterministic across seeds")
Evidence: the walker ignores its seed and holds no shared state, so `assertDeterministic` passes for any harness that doesn't crash. The spec has no negative case. The AC4 acceptance specs do cover leaks, so coverage exists elsewhere. This is only a clarity issue for the fixture as documented reuse material.
Fix: add one line to the test or fixture comment saying the negative cases live in the acceptance specs, or drop the case.

### F6 [low] Process record: one commit for a five-step plan, and inconsistent dates
Where: tracker/issues/active/c0010/c0010-game-sim-harness.md (Verification log, Implementation steps); tracker/issues/active/c0010/spend.md
Evidence: the plan says to commit after each of five steps, but there is a single implementation commit (spend shows 1 commit, 1.6 minutes for 524 lines). The verification log is dated 2026-09-29 and the spend row 2026-09-30. Nothing is functionally affected.
Fix: none required for merge. Optionally correct the log date.

## Judged criteria (code mode only)
None defined for c0010 or R0003.

Verdict: approve
