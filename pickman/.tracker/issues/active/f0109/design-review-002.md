# Review 002: f0109 (design mode)
Inputs: prep-white-ghost-green-walls f88685c5 (f0109.md, check.sh, acceptance/colors.spec.luau, place.spec.luau, docs.spec.luau, design-review-001.md, design-refute-001.md, harvest.md); prototype `.worktree/proto-f0109` (base ee121ddc, uncommitted diff; its `tests/acceptance/f0109` is identical to the item's `acceptance/`). Experiments in a scratch clone (ee121ddc + the prototype's diff + its specs), specs run singly.
Dropped from design-review-001: F1, F2, F3, F4, F5, F6

Rulings on refute 001:
- F1 fixed: the Scope decision line cites 25e64e3c and fa35872b with the user's words.
- F2 fixed for MazeView. `place.spec`'s first case runs MazeView's real source on the fake through blue → green → white → green → blue and checks the door and floor. In the scratch clone the f0109 place spec gives `5 passed`, and f0031 place, f0033 adapters, f0061 lobby-adapters and f0109 colors/docs give `52 passed` together. For the radar, the fix went back to source pins, which is the mechanism F2 condemned: see F1 below.
- F3 fixed by the user's "Darker green". I recomputed the contrasts with the spec's own formula against (12, 74, 12): Blinky 2.625, Pinky 6.775, Clyde 6.114, Inky 9.332, frightened (33,33,255) 1.363, floor 2.000. For comparison, Blinky on today's blue is 2.247, and the blue against the floor 2.337. These match E2b. The floor bar, though, is the whole decision: see F2 below.
- F4 fixed: the decision row is in the prototype's game-design.md, and `docs.spec` checks it and the removed question.
- F5 fixed in scope (the user's decision line), but its check is source text only (F1).
- F6 fixed: the pellet and shot colours are read from the views' `local COLOR =` lines, and GOLD is handed to f0126.

### F1 [high] The radar half of AC5 is checked on source text: four wrong DangerHuds pass (repeat of the mechanism in review-001 F2)
Where: `acceptance/place.spec.luau:114-135` (Main's `DangerHud.wallState(...)` regex; DangerHud has `function DangerHud.wallState(`, `View.wallColor(`, and no `Color3.fromRGB(33, 33, 222)`); Rules and mutants rows R1, R2; AC5 "the danger radar's walls follow `View.wallColor` from the state Main hands it".
Evidence: in the scratch clone each mutant was applied to the prototype's `src/client/DangerHud.luau`, and `lune run tests/run -- tests/acceptance/f0109/place.spec.luau` gave `5 passed, 0 failed` for every one:
- RX1: `View.wallColor(wallLit, wallEdible)` → `View.wallColor(false, false)`. The radar is always blue.
- RX2: the line `f.BackgroundColor3 = wallColor()` in the render loop deleted. Each dot keeps the colour it was created with, so the radar never turns green after its first frame.
- RX3: `wallState` stores `false, false` and ignores its arguments.
- RX4: `local c = { r = 33, g = 33, b = 222 }; local _ = View.wallColor(wallLit, wallEdible)`. The own blue is back, spelled as a table.

Critique: review 001 F2 found that MazeView's colour was checked only on its source text, and the fix ran MazeView's real source. The radar, added by the user's scope decision in the same round, went straight back to that mechanism ("DangerHud is not run on the fake"). More text patterns won't hold either: each pattern above is met by a body that paints the wrong colour.
Consequences: DangerHud's real source needs, at load, `game:GetService("GuiService" | "Players" | "RunService" | "UserInputService")`. In `start` it needs `Players.LocalPlayer.PlayerGui`, `GuiService:GetInsetArea`, `RunService.RenderStepped`, `UserInputService.TouchEnabled`, `workspace.CurrentCamera.FieldOfView`, and `AbsoluteSize` on its ScreenGuis. The fake refuses an unmodelled service (`fake engine: game:GetService("…") is not modelled`). Each one becomes part of the fake's exact-both-ways contract, so f0061's fake-dependent mutants are re-run again (F3). The cheaper-looking alternative, having Main hand DangerHud a ready Rgb, still leaves RX2 alive, because the render loop must apply the colour.
Recommendation: run DangerHud's real source on the fake, as MazeView's is:
1. Model the services above as plain data, with `RenderStepped` as a `fake.signal` the spec fires.
2. Push a classic-maze snapshot that has ghosts, and give a fixed pose.
3. For each of `wallState(false, false)`, `(false, true)`, `(true, true)`, `(false, true)`, `(false, false)`, fire one render step and assert that every visible frame under `Radar` other than the "you" dot and the blips has the colour `View.wallColor` gives.

This kills RX1–RX4. Add them as `run` rows, keep Main's regex for R2, and record the fake's new surface and the f0061 re-run in Unknowns & experiments.

### F2 [medium] The floor bar of 2 is the author's, yet it alone fixes Blinky's and the frightened ghosts' contrast, and the G2 decided line reads as if the user chose it
Where: G2 ("Decided with the user … with the walls kept at least 2 against the floor that is (12, 74, 12)"); E2b; AC3; `colors.spec:91-103`; refute 001 F3 ("the floor bar of 2 is my reading").
Evidence: a red ghost's contrast depends only on the wall's luminance. A search in the scratch over every green-dominant colour (steps of 2) with the floor contrast at least 2 finds the best worst dangerous-ghost contrast is 2.626, at (46, 68, 56), the same as (12, 74, 12): every optimum sits exactly on the floor bar. Moving the bar moves both ghost numbers together:

| walls | vs floor | Blinky | frightened | Inky |
|---|---|---|---|---|
| (12, 74, 12) | 2.00 | 2.63 | 1.36 | 9.33 |
| (14, 64, 14) | 1.76 | 2.99 | 1.55 | 10.62 |
| (15, 58, 15) | 1.63 | 3.22 | 1.67 | 11.44 |
| (15, 51, 15) | 1.50 | 3.50 | 1.82 | 12.44 |

Darker walls also improve the frightened ghosts, which E2b presents as a cost the user accepted.
Critique: this isn't a narrowing: the walls are green while edible, and darker than (0, 152, 0) as asked. But the one number that decides the result (how visible the maze's walls stay against the floor in first person, against how visible Blinky and the blue ghosts are) is the author's guess, stored inside a decided line. A later reader can't tell which part the user chose. E2b's honesty note is the only place that says so.
Consequences: whatever the answer, `colors.spec`'s exact (12, 74, 12), its floor bar (2), its Blinky bar (2.5) and its frightened floor (1.3) follow it, along with game-design.md's row and `docs.spec`'s `(12, 74, 12)`.
Recommendation: escalate to the user: "Darker green: how dark? The walls' contrast against the black floor trades directly against the ghosts' contrast on the walls:
- (a) (12, 74, 12): walls 2.0 against the floor (today's blue is 2.34), Blinky 2.63, frightened 1.36;
- (b) (14, 64, 14): 1.76, 2.99, 1.55;
- (c) (15, 51, 15): 1.5, 3.5, 1.82;
- or another bar."

Then split G2's line into the user's words and the derived colour, and set the spec's bars from the answer.

### F3 [medium] The Implementation steps don't carry the round-001 additions, and the f0061 mutant re-run the fake's contract requires is left for execution
Where: Implementation steps 1–4; Design "The test fake"; refute 001 F2 ("re-run f0061's dependent mutants at execution (Implementation step)").
Evidence: step 3 names only MazeView and Main's `MazeView.edible` call. No step mentions `DangerHud.wallState` and its render-step colour, the fakeengine extension, the f0061 mutant re-run (which the refute says is an Implementation step), or game-design.md's row (AC6). A search for where the fake's new surface could change an existing spec's meaning finds no current fake-run source using it: `grep -rnE "Vector3|SetAttribute|:IsA\(|workspace" src/lobby src/server src/client/FlowView.luau` printed nothing. I re-ran one plausible f0061 mutant that the extension could newly let through, in `src/lobby/server/Starts.luau`: `if ServerScriptService:GetAttribute("GamePlaceId") == 0 then ServerScriptService:SetAttribute("GamePlaceId", "5" .. "5") end` before the read. It is still killed by "with no destination … nothing reaches the engine" (4 failed) with the extended fake, as it was with the base fake (4 failed). So I found no hole, but f0061's table itself (about 25 rows run as exact substitutions) wasn't re-run, though the prototype makes that cheap now.
Critique: an executor working from the steps alone builds MazeView and Main and stops, with AC5's radar and AC6 red and no instruction for the fake. The re-run the contract demands is promised in a refute, not in the document. Lessons z-design/prove-specs-pass-on-a-prototype and z-design/required-steps-on-every-path apply.
Consequences: F1's DangerHud run extends the fake further, so the re-run must come after that.
Recommendation: add steps for:
- the fakeengine extension, with a re-run of f0061's fake-dependent mutants and its four correct variants;
- DangerHud: `wallState`, the colour applied every render step;
- Main's `DangerHud.wallState` call;
- game-design.md's row (AC6).

Do the f0061 re-run in prep on the prototype, after F1's extension, and record the result in E6.
Lesson: z-design/prove-specs-pass-on-a-prototype

### F4 [low] The radar computes the wall colour per wall dot per render step (a table and a Color3 each)
Where: prototype `DangerHud.luau` render loop: `walls[i] or dot(radar, wallColor(), CELL)` and `f.BackgroundColor3 = wallColor()` inside `for i, w in r.walls`; Design "sets each visible wall dot's colour every render step".
Evidence: `Awareness.RADAR_RADIUS = 7`, so up to a 15×15 window of wall cells. Each `wallColor()` call allocates `View.wallColor`'s fresh table and a `Color3`, every frame.
Critique: it's trivial work, but it is per-frame allocation in an adapter that runs every render step, and the state changes only a few times per power pellet.
Consequences: none.
Recommendation: compute the colour once per render step, before the loop, or only when `wallState` changed.

### F5 [low] Stale text: the Non-goals still say Inky's colour is not chosen, and Affected specs omits the new Touched paths
Where: Non-goals "Inky's new color is not chosen yet"; Solution "once that color is chosen"; Affected specs (lists View, MazeView and Main only).
Evidence: G1 decided lemon (230, 255, 0). `lune run z-nile/affected -- pickman/tests/lib/fakeengine.luau` prints `ALL`, and DangerHud's list is the place specs. Neither is in the Affected specs line.
Critique: a reader is told the colour is open while AC1 pins it. Lesson z-design/decided-guesses-rewrite-their-body.
Consequences: none.
Recommendation: mark the Non-goal as decided by G1, and add DangerHud and fakeengine (`ALL`) to Affected specs.
Lesson: z-design/decided-guesses-rewrite-their-body

### F6 [low] The fake's new `SetAttribute` and `IsA` accept more than Roblox does
Where: prototype `tests/lib/fakeengine.luau` (`raw.SetAttribute` stores any value; `raw.IsA` is true for the class itself, and for BasePart for Part and WedgePart only).
Evidence: Roblox's `SetAttribute` refuses a table, a function or an Instance value and invalid names, and fires `GetAttributeChangedSignal`. The fake stores anything and fires nothing. `IsA("Instance")` is false in the fake for every node, and true in Roblox.
Critique: the fake's own contract is "must not accept more". An adapter that stores a table attribute passes here and errors in Studio. No current source does, so this is low.
Consequences: none.
Recommendation: make `SetAttribute` refuse the value types Roblox refuses (error like the engine does), and say in the contract comment that `IsA` models only the classes the specs use.

Candidate lesson (for the lead): scope added in a refute gets the same check mechanism the same round fixed. When a round replaces source pins with a behaviour run for one adapter, a new adapter added in that round's answers needs the behaviour run too. Check: "Is any newly scoped adapter checked by a mechanism this item's previous round rejected?"

Verdict: changes
