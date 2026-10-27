# Review 003: f0109 (design mode)
Inputs: prep-white-ghost-green-walls dc2405a3 (f0109.md, check.sh, acceptance/colors.spec.luau, place.spec.luau, docs.spec.luau, design-review-002.md, design-refute-002.md, harvest.md, z-nile/skills/z-design/lessons/scope-added-in-a-refute-gets-the-same-check.md); prototype `.worktree/proto-f0109` (base ee121ddc, uncommitted diff; its `tests/acceptance/f0109` is identical to the item's `acceptance/`); prep-console-gamepad 4fcd1d79 (f0146, for the fake engine's blast radius). Experiments in a scratch clone (ee121ddc + the prototype's diff + its specs).
Dropped from design-review-002: F1, F2, F3, F4, F5, F6

Rulings on refute 002:
- F1 fixed for the mechanism. DangerHud's real source runs on the fake. I checked that the case reads the colours it claims. It counts every visible child of `Radar` except the "you" dot (255,255,0) and the hunting blip (255,60,60), and requires at least one counted dot. A wall painted in either excluded colour would leave zero counted dots and fail. Any other colour on the radar shows up in `seen` and fails. The case passes on the prototype, so no stray child (a UICorner, a frightened blip) is in the count at step 61. But the five states it walks (the list review 002 F1 itself prescribed) leave out the one flash state the game produces: see F1.
- F2 fixed. The user chose (14, 64, 14). I re-ran the spec's own formulas: Blinky on the green 2.99, frightened 1.55, floor 1.76, Inky 10.62. Gold (255, 215, 0) is 31.4 CIE76 from lemon and 33.3 from Clyde. The spec's bars (2.9, 1.7, 1.5) sit just under those values.
- F3 fixed, and the f0061 re-run holds. In the scratch clone, every spec that requires `fakeengine` passes: `grep -rlE fakeengine tests | grep spec.luau` lists 10 files (f0024, f0025, f0026, f0061 lobby-adapters, f0065 ×4, f0109 place, flow-rank-prompt), and they give `121 passed, 0 failed`. The full pickman suite gives `1418 passed, 0 failed, 209 spec files`. f0061's lobby-adapters is `27 passed` on the prototype. I applied the mutants as exact substitutions:
  - V3 (`button.Position = UDim2.fromOffset(5000, 5000)`): 6 failed.
  - V2 (`button.Size = UDim2.fromOffset(200, 40)`): 6 failed.
  - V1 (`backdrop.Size = UDim2.fromOffset(100, 100)`): 6 failed.
  - V5 (`SetAttribute("GamePlaceId", 55)` before the read in Starts.luau): 4 failed.
  So the view constructors are scoped to `fake.module`, and the lobby still lacks `fromOffset`. One more thing is shared: `LOGIC` now serves View, Awareness and Hud to every environment. Before, a lobby or server adapter requiring them got `no module for require`. The real lobby carries the shared Logic, so this moves the fake toward the engine, not past it. It only makes E8's "gains only `:SetAttribute` and `:IsA`" inexact (F2).
  Outside the promoted specs, one other prepared item's spec uses the fake: f0146 `acceptance/flow.spec.luau` (searched over origin/main and every `prep-*`/`proto-*` branch with `git grep -lE "fakeengine|fake\.module" <branch> -- 'pickman/.tracker/issues/**/*.luau'`, done/ excluded; the only hits were active/f0065 ×4, f0109 place, and f0146 flow). It uses `fake.client` and none of the new surface. See F3 for the shared edit.
- F4 fixed: the colour is computed once per step, before the loop.
- F5 fixed. One stale reference remains (F2).
- F6 fixed: `SetAttribute` refuses a bad name and table, function, thread and Instance values (`raws[value]`, keyed by proxy). The `IsA` limit is stated.

### F1 [high] Neither adapter run ever sees the real level-clear flash (lit, not edible), so a MazeView and a radar that show the flash only while edible pass the full gate
Where: `acceptance/place.spec.luau`: the MazeView case (edible → flash on → flash off → edible off: states (F,F), (F,T), (T,T), (F,T), (F,F)) and the radar case (the same five states); AC5 "white in the flash"; Rules and mutants rows N8, RX1–RX4.
Evidence: the game never hands the adapters (lit = true, edible = true). `Game` sets `g.frightened = 0` when the level is cleared (`src/shared/Logic/Game/init.luau:122`: `g.phase, g.timer, g.frightened = "levelclear", g.config.levelClearTicks, 0`), and `Flow` lights the walls only in `levelclear` (`Flow/init.luau:67`). So every real flash frame is (true, false). Both cases test the flash only as (true, true). `View.wallColor(true, false)` is pinned in colors.spec:84, but only on the pure rule. In the scratch clone, with both of these applied:
- MM1 in MazeView's `wallColorOf`: `View.wallColor(Lit == true and Edible == true, Edible == true)`;
- DM1 in DangerHud's `wallColor`: `local c = if wallEdible then View.wallColor(wallLit, wallEdible) else View.WALL_COLOR` (the radar never had a flash, so "add the edible case" is the natural edit);
f0109's specs give `14 passed, 0 failed`, and the full pickman suite gives `1418 passed, 0 failed, 209 spec files`. With MM1, the maze's level-clear flash (R0015) never shows. f0031 pins only `function MazeView.flash(` and Main's call, as source text. With DM1, the radar never flashes.
Critique: AC5's "white in the flash" can be passed by an implementation that never shows the flash in play. And the flash, which f0109 rewrites inside MazeView, loses its only behavioural guard. This is lesson zz-test/seed-every-enumerated-case: the adapters walk lit × edible, and the one combination that matters is missing. The tempting fix is to add (true, false) to the radar list only, which leaves MazeView open.
Consequences: (true, true) stays useful. It pins the precedence the Design states (the flash wins), even though the game doesn't produce it today. Add nothing that assumes (true, true) is unreachable. No new rule or state.
Recommendation: in both cases, walk all four combinations, with the real flash among them. MazeView: blue → `flash(true)` white → `flash(false)` blue, before the edible part of the sequence. Radar: add `{ true, false }` (for example `{F,F}, {T,F}, {F,F}, {F,T}, {T,T}, {F,T}, {F,F}`). Add MM1 and DM1 as `run` rows, and record their kill in Unknowns & experiments. Optionally, take the flash state from a real level-clear frame (`Flow` overlay plus `View.edible` of a `levelclear` PlayFrame), so the spec walks what the producer hands over.
Lesson: zz-test/seed-every-enumerated-case

### F2 [low] Stale numbers and references after the gold and the fake changed
Where: Design "Inky's colour" (f0109.md:39): "CIE76 distance ≥ 45 from every other drawn colour" next to "lemon is 31.4 from it"; E1 (line 73): "Lemon … clears every bar: … gold 45.4 (its nearest)"; G1 (line 160): "45.4 from f0126's gold"; E8: "the lobby's environment otherwise gains only `:SetAttribute` and `:IsA`" (it also gains View, Awareness and Hud through `require`); prototype `tests/lib/fakeengine.luau:24` "(the lobby's environment is unchanged: f0109's re-run of f0061's mutants, E6)" (the re-run is E8, and the environment did change, by those methods).
Evidence: `grep -n "45\.4\|≥ 45" f0109.md` hits lines 39, 73 and 160. My recomputation with the spec's formula gives lemon–gold 31.4. That passes the bar of 30, but it is not 45.
Critique: lesson z-design/restated-rules-move-together. A reader is told the margin is 45 when it is 31.4, and that the lobby's environment is unchanged when it isn't.
Consequences: none.
Recommendation: restate the margin as "≥ 30 (lemon 31.4 from gold, its nearest)" in the Design, E1 and G1. Fix E8's and the fake comment's wording and the E-number.
Lesson: z-design/restated-rules-move-together

### F3 [low] f0146 changes the same fake engine and `Main.client.luau`, and the Regression guard doesn't name it
Where: Regression guard; f0146 (prep-console-gamepad 4fcd1d79) f0146.md lines 163, 181, 253: "`tests/lib/fakeengine.luau` (its Logic table learns `Pad`)", and it changes `src/client/Main.client.luau`.
Evidence: f0109 rewrites the `LOGIC` table to multi-line form and adds View, Awareness and Hud. f0146 adds Pad to the same table. Both edit Main.client.luau. The fake's contract says f0061's dependent mutants are re-run "whenever it changes".
Critique: whichever item lands second hits a textual conflict in `LOGIC` and Main, and owes the fake-contract re-run. Neither document says so.
Consequences: none beyond naming it.
Recommendation: add a Regression guard line: f0146 also extends `LOGIC` (Pad) and edits Main. Whichever lands second merges both module sets and re-runs f0061's V1–V3 and V5, plus every fake-engine spec (the 10 files above).

Candidate lesson (for the lead): a spec that walks an adapter through states walks the states the producer actually hands it, not only the ones the rule's table lists. Here the game's only flash is (lit, not edible), because the level clear zeroes the power timer. Check: "For each input combination this adapter can receive, which ones does the real producer emit, and is each one in the case?" (It may fit as a note on zz-test/seed-every-enumerated-case.) It's also a reviewer lesson: review 002 F1 prescribed the incomplete state list.

Verdict: changes
