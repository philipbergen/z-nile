# Review 001: R0009 (code mode)
Inputs: HEAD 5bd5c6b (R0009-pellets-and-mechanics) against origin/main a3ac240 (merge base 9d20edc); R0009.md and check.sh; f0016, f0017, f0018, c0056 documents, check.sh files and acceptance specs; the sequestration diff against b761e42 ("tracker: start R0009").
Runs (all on 5bd5c6b): `scripts/check.sh --full` GATE PASSED (567 passed, 94 files); `tracker.sh check` f0016 4/4, f0017 2/2, f0018 6/6, c0056 2/2; `bash tracker/rafts/active/R0009/check.sh` 8/8; `tracker.sh promote-check R0009` OK. A trial merge with origin/main (resolved to either side of the one conflict) gives 581 passed / 0 failed for every spec, and 8/8 for the raft check.
Sequestration: the diff against b761e42 is exactly what c0056 describes. In `f0016/eating.spec` and `f0018/flow.spec`, the mixed-type row literals are rebuilt with a local `row(...)` helper that returns `{ ... }`, so the values and their order are the same and they are still compared with `toEqual`. In `f0018/game.spec`, `_, ok =` becomes `events, ok =`, and `events` is not read again after that. The raft check.sh `spec()` helper gains the `active/` path. Nothing else changed and no assertion was weakened, so there is no sequestration finding.
Mutants run by the reviewer on a scratch copy: decide `moving` after `Game.step`, clear before power, stall not reset on teleport, intents queued through pauses, pellets reset on respawn, play-again `jumpTick = tick`, extra life at `>`, power extends, frame `timer` hard-wired, wrap without `jumpTick`. The specs kill every one. Three survive. Two are equivalent with this code: the debt paid only while `move.moving` (a stop needs the tile centre, which comes after the debt is paid), and `kill` clearing `stall` (no movement while dying, and the respawn clears it anyway). The third is F4.
Observed criteria are listed for the human: f0016 OC1 (the eating hitch) and f0018 OC1 (countdown, respawn, level change). f0017 has none. There are no Judged criteria.

### F1 [medium] The branch conflicts with main in the sequestered raft check.sh, and main has already fixed the same bug a different way
Where: `tracker/rafts/active/R0009/check.sh:15-25`; main's 078823d "tracker: fix R0009 check.sh spec path (#31)"; c0056.md Solution ("A fourth fix")
Evidence: `git merge-tree --write-tree HEAD origin/main` reports `CONFLICT (content): Merge conflict in tracker/rafts/active/R0009/check.sh`. Main's PR #31 rewrote the same `spec()` line to `… || echo "$d/$(scripts/tracker.sh find "$1")/acceptance/$2"`. The branch has a three-way `if/elif/else` that hard-codes `tracker/issues/active/`. The branch is also 3 commits behind main, including R0017 (`Session.STEP_RATE`, `newClock(Session.STEP_RATE)` in `Sessions.luau`). That part merges cleanly next to `GAME_CONFIG` and `Session.frame`, and the merged tree passes every spec. But the PR cannot land as it stands, and the conflict is in a sequestered file.
Critique: the author may be tempted to keep the branch's version, or to merge the two into a third variant. That would add a third version of a sequestered file, and it would no longer be the one the human reviewed and landed in #31.
Consequences: if the conflict is resolved to main's version, the c0056 "fourth fix" no longer exists in the PR. c0056.md, its Verification log and R0009's "Addressed during execution" would then describe a change that isn't in the PR. The sequestration diff against b761e42 would show main's line, which landed through review on main, plus the three type-only spec edits.
Recommendation: merge origin/main and resolve the conflict by taking main's version of the file unchanged. I checked it on the trial merge: `spec()` through `tracker.sh find` resolves f0017 and f0018 to `tracker/issues/active/…` and f0013 to `tests/acceptance/f0013`, and RC1 and RC2 pass (9/9). Then update c0056.md (Solution, Verification log) and R0009's "Addressed during execution" to say that the raft check.sh path fix arrived from main (#31) and that c0056 is only the three spec typing fixes. Re-run `bash tracker/rafts/active/R0009/check.sh` on the merged branch.

### F2 [medium] c0056's check.sh stops working once its specs are promoted
Where: `tracker/issues/active/c0056/check.sh:6-9`
Evidence: AC2 hard-codes `tracker/issues/active/f0016/acceptance/eating.spec.luau`, `…/f0018/acceptance/flow.spec.luau` and `…/game.spec.luau`. `tracker.sh done` moves those files to `tests/acceptance/<id>/`. After that, `scripts/tracker.sh check c0056` (or a re-run of the raft check from `done/`) fails AC2 because the files are missing. The testing skill requires that "a `check.sh` is re-runnable once `tracker.sh done` has moved its specs". `done` runs the check before it promotes, so `done` itself succeeds and nothing catches this.
Critique: the obvious fix is to point AC2 at `tests/acceptance/…`. That would break the check now, before promotion.
Consequences: the paths have to resolve in both places, and for two different issues (f0016 and f0018), not for c0056's own id. That is the same problem main's `spec()` solves.
Recommendation: resolve each path the way main's raft helper does. Use `tests/acceptance/<id>/<name>` if it exists, else `$(scripts/tracker.sh find <id>)/acceptance/<name>`, in one `check` per AC as now. This file was written during execution as c0056's own check, so it is not under the b761e42 sequestration, but say in c0056.md that it changed. Verify with `scripts/tracker.sh check c0056` now. On a scratch copy, also verify with the three specs `git mv`'d to `tests/acceptance/<id>/`.

### F3 [medium] c0056's rework is booked to f0017, so the rework metric shows 0
Where: `tracker/rafts/active/R0009/spend.md` (c0056 row: 0 lines, 0.0 min, 0 commits); `tracker/issues/active/f0017/spend.md` rows 2-3; c0056.md "Touched modules" (empty), `design: draft`
Evidence: commits 6b4c88f and 5bd5c6b are titled "c0056: …", but their trailers say `Issue: f0017 +0/-0 10.0m` and `Issue: f0017 +0/-0 5.0m`, because they were attributed by focus. f0017 shows 35 minutes, 15 of which are c0056's. The tracker skill says an emergent issue's "spend counts toward its own type, which is how rework is measured". The raft reports 0% rework when it was about 15/85 (18%). c0056.md's Design, Touched modules and Rules sections are empty template stubs.
Critique: hand-editing `spend.md` is forbidden ("never edit by hand"), so the tempting fix of moving the rows isn't allowed.
Consequences: any further c0056 work, such as F1 and F2, would be misattributed the same way unless it is committed with `--issue c0056`.
Recommendation: fill in c0056's Touched modules: the three spec paths and `tracker/issues/active/c0056`, plus `tracker/rafts/active/R0009/check.sh` if F1 doesn't drop that change. Commit all c0056 work for F1 and F2 with `tracker.sh commit --issue c0056`. Record the 15 misattributed minutes in R0009.md under "Addressed during execution" and in the final report, so that the human can correct the metric. Don't edit spend.md.

### F4 [low] No spec checks that the eating pause uses the tick's full speed when a pellet is eaten on a step that is still paying a pause
Where: `src/shared/Logic/Session/init.luau:233-246` (`eat(…, speed, out)`)
Evidence: the mutant `eat(…, speed - owed, out)` passes every spec. The f0016 design says "a dot's pause is computed at the speed of the tick it was eaten in", and the code does use the full speed. With the shipped speeds (base 30, at most 38) a tile is never entered on a step that is still paying, so players can't see this today. `Session.new` accepts base speeds up to 96, though. On the corridor `{"############","#.........P#","##########.#","############"}` at speed 90 with `eatSlowdown = true`, the real code is at x = 5.125 at tick 9 and the mutant at 4.933.
Critique: a future change (a higher base speed, or a refactor that moves the stall subtraction) can silently shorten the pause.
Consequences: none beyond one new case.
Recommendation: add a case to the executor-owned `tests/unit/Session/session.spec.luau` with the corridor above at speed 90. Assert the position at tick 9 (5.125) and that ticks 8 and 9 move 0.375 and 0.375 tiles. Don't touch the acceptance specs.

### F5 [low] Pellets.eat's doc comment is above Pellets.points
Where: `src/shared/Logic/Pellets/init.luau:64-66`
Evidence: `-- Removes and returns what was on the tile; nil if nothing was.` is followed by `-- Points for eating one.` and then `function Pellets.points`. `Pellets.eat` (line 70) has no comment.
Critique / Consequences: none.
Recommendation: move the first line above `Pellets.eat`.

## Judged criteria (code mode only)
None in this raft.

Verdict: changes
