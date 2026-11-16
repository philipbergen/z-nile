# Review 001: R0056 (code mode)
Inputs: f47cacce (branch R0056-white-ghost-green-walls) against origin/main 6390a4bc (`./zn sync --fetch`; `git merge-tree` of the two: clean); `git diff origin/main...HEAD` (View, MazeView, DangerHud, Main.client, tests/lib/fakeengine, game-design.md, f0109.md); f0109.md, R0056.md, both check.sh files, f0109's acceptance specs (colors, place, docs). Mutants run in a scratch clone of the branch (outside the repository), each file restored with `git checkout` after its run.

### F1 [medium] AC5's "Main tells MazeView each frame" is checked by a grep that a Main which never turns the walls green passes
Where: `pickman/src/client/Main.client.luau:52-59`; f0109 `acceptance/place.spec.luau` "Main hands the lit and edible state to MazeView and to the danger radar each frame"
Evidence: run against the three f0109 specs in a scratch clone (`lune run tests/run -- colors place docs`):
- M2, the `MazeView.edible(model, View.edible(frame.play))` call moved into the `if model and overlay.flash ~= lit then` block (so it runs only when the flash toggles, and the maze never turns green during play): `14 passed, 0 failed, 3 spec files`.
- M3, `if model then` before that call changed to `if model and false then`: `14 passed, 0 failed, 3 spec files`.
- For contrast, the mutant that changes the call's argument (`View.edible(frame.play) and lit == false`) is killed: `13 passed, 1 failed`.
Both survivors type-check (they only move or guard an existing call). The place case greps the call's text; the Rules and mutants table lists only N7 (the call dropped). No other spec on main runs Main's source (f0126's `views.spec`, the first Main harness, is not landed: `git grep -n "rewall\|MarkedWall" origin/main -- pickman/src` is empty).
Critique: the code on this branch is right (the call is at the handler's top level, every frame), so this is not a defect today; it is a guard missing for the most likely future regression: the two adjacent `if model` blocks invite a merge (f0146 and f0126 both edit these lines, per the Regression guard) to fold the new call into the flash block, and every spec stays green. The check itself is sequestered, so it can't be strengthened here. The tempting fix is a second grep that the call isn't inside the flash block.
Consequences: a structural grep pins one shape of the handler and breaks on a correct refactor (an early return, a helper that does both calls); a behaviour case needs Main loaded on the fake engine, which today has no Main harness (pickman-test lesson stub-loaders-fall-back: such a harness must be open on every side).
Recommendation: either (a) add a non-sequestered behaviour case once a Main harness exists: fire two frames with `play.frightened` 0 then > 0 and `overlay.flash` unchanged, and expect the walls green (kills M2 and M3); f0126 brings that harness, so file it now as an issue that depends on f0126 and say so in the refute; or (b) if you'd rather guard it in this PR, add a small own place spec that asserts the `MazeView.edible(` and `DangerHud.wallState(` calls sit at the handler's top level (indent one tab inside the `Connect(function(frame` body), and record the deviation (a test file outside the Touched modules) in the Verification log. Either way, add M2 and M3 to the record of mutants run.
Lesson: zz-test/pin-call-site-arguments

### F2 [medium] The fake engine's new `:SetAttribute` refusals have no case: deleting them leaves every spec green
Where: `pickman/tests/lib/fakeengine.luau:155-174`
Evidence: in the scratch clone, with `raw.attributes[attribute] = value; if true then return end` inserted at the top of `raw.SetAttribute` (no name or value check at all), every spec that uses the fake (`.tracker/issues/active/f0109/acceptance/*.spec.luau tests/acceptance/{f0061,f0065,f0024,f0025,f0026}/*.spec.luau tests/place/flow-rank-prompt.spec.luau`): `263 passed, 0 failed, 31 spec files`, the same as without the mutant. `grep -rln fakeengine pickman/tests` finds no spec of the fake itself.
Critique: the fake's contract (its header: "must not accept more") and the Design (design review 001 F2, 002 F1) make the refusals part of what f0109 delivers: a wrong adapter that stores a table or an Instance, or uses a bad name, must fail on the fake as it would in Roblox. Nothing pins them, so they can be weakened silently (zz-test lessons guard-needs-its-own-case, refusals-tested-on-both-sides).
Consequences: a refusal case must also show the fake accepts what Roblox accepts at the edge, or a stricter fake (refusing a 100-character name, a number, a boolean, nil to clear) would pass. Note one divergence the case will expose: Roblox accepts Color3, Vector3, UDim2 and other datatypes as attribute values, which are plain tables in the fake, so the fake refuses them; today no adapter stores one, but the contract says "must not accept less" than the engine, so the header should name this limit.
Recommendation: add a spec of the fake (for example `pickman/tests/place/fakeengine-attributes.spec.luau`, recorded as a deviation in the Verification log): a 100-character name of letters, digits and `_` is accepted and a 101-character one, `""` and `"a-b"` refused; a string, number, boolean and `nil` (which clears) accepted, and a table, a function, a thread and another node refused with the "Instance" message for the node. Add a line to the fake's header that datatype values (Color3, …) are refused here although Roblox accepts them.
Lesson: zz-test/refusals-tested-on-both-sides

### F3 [low] The fake engine's header cites the wrong experiment for the f0061 re-run
Where: `pickman/tests/lib/fakeengine.luau:24` ("f0109's re-run of f0061's mutants, E6")
Evidence: f0109.md's Unknowns: E6 is the first prototype run; the f0061 re-run that moved the constructors into `fake.module`'s own environment is **E8** (the Design's test-fake paragraph and Implementation step 3 both say E8).
Critique: the next author extending the fake follows this pointer to find what must be re-run.
Consequences: none.
Recommendation: say E8.

### F4 [low] During the power period the radar's walls drop to 1.76:1 against its black backdrop, the opposite of the user's "the radar needs to be more visible"
Where: `pickman/src/client/DangerHud.luau:85-91` (radar background `Color3.new(0, 0, 0)` at transparency 0.35; wall dots now `View.wallColor`)
Evidence: the colours spec's own figure: `contrast(WALL_EDIBLE_COLOR, FLOOR)` = 1.76 (AC3), against 2.34 for the blue (E2b); the radar's backdrop is the same black.
Critique: this is the user's decision (f0109 Problem, Scope decision 2026-10-25: the radar's walls follow the maze walls' rule), and the radar's visibility is f0158's, so nothing here should change. But f0158's design should know the radar is dimmest exactly while the ghosts are edible.
Consequences: none for this PR.
Recommendation: mention it on the PR and in f0158's issue when it is next prepped (the lead adds a note there; no product change here).

## Judged criteria (code mode only)
None: f0109 has no Judged criteria.

Other checks, with nothing found:
- Gate: `z-nile/check.sh --full` in the worktree at f47cacce: GATE PASSED (full), exit 0; pickman 1415/1415, z-nile 1222/1222, 0 lint errors, 0 warnings, 0 parse errors (wall 1193 s). `./zn check f0109`: 6/6 criteria passed. f0109's three specs in the scratch clone: `14 passed, 0 failed`.
- Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` prints nothing; `git diff --summary origin/main...HEAD` has no `mode change` (only `create mode 100644 pickman/.tracker/rafts/active/R0056/spend.md`).
- Mutants killed (each `13 passed, 1 failed` or worse): MazeView `flash` and `edible` painting before setting their attribute (MV1, MV2); a build wall in a fixed blue (MV3) or in `View.wallColor(false, false)` (MV4); `wallColorOf` ignoring `Edible` (MV5); DangerHud colouring only new dots (DH1) and `wallState` swapping its arguments (DH2); `View.edible` as `>= 0` (V1); `wallColor` checking edible before lit (V2, 2 failed).
- Correctness: `Game` zeroes `frightened` on death (`Game` line 131) and at level clear (line 122), so the walls are blue in the dying and level-clear phases and the flash is the real (lit, not edible) state; a maze rebuilt mid-run starts with no `Lit`/`Edible` attributes and `wallColorOf` treats them as false; Main's next frame sets `Edible`. `MazeView.flash` now returns early when `Lit` is unchanged, which matches Main's own `lit` gate.
- Removed names: `git grep -nE "inky|0, ?255, ?255|33, ?33, ?222|local WALL|LIT\b|MazeView\.flash|wallColor" origin/main -- 'pickman/.tracker/**/*.spec.luau' 'pickman/tests/**/*.spec.luau'` hits only f0126's sequestered `parts.spec` (its 3-argument `View.wallColor`, which f0126's Regression guard says it builds on after f0109) and c0063's count of overlay uses (`narrowed.spec`: 6/6 on the branch). Remaining hard-coded `(0,255,255)` and `(33,33,222)` in `src` are the blaster's beam and the HUD frame, which the Design keeps.
- Architecture: no new Logic-to-Logic require (View already requires Session); Main's new require of View is a client adapter reading Logic; colours stay presentation on the client from the replicated frame, no server change. Performance: one comparison and one attribute read per frame; the radar computes one colour per render step; MazeView repaints only on a change.
- Repository safety: the diff adds no command that writes anything; the fake engine's additions are in-memory; no guard file is touched.

Candidate lesson (for the lead): **A wiring check pins where the call runs, not only that it exists** (zz-test, both): a grep for a call in Main proves the call is written, not that it runs every frame; check: for each "each frame" wiring rule, which mutant moves the call into a neighbouring conditional block, and does a spec fail for it?

Verdict: changes
