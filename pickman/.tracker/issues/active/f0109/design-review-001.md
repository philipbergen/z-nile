# Review 001: f0109 (design mode)
Inputs: prep-white-ghost-green-walls 6fa1090e (f0109.md, check.sh, acceptance/colors.spec.luau, acceptance/place.spec.luau); prototype `.worktree/proto-f0109` (base ee121ddc, uncommitted diff; no drift in `pickman/src` or `pickman/tests` to origin/main 944e5c19); `./zn capture f0109` (25e64e3c) and the item's history; f0126 (prep-risky-wall-picks 179ee87a) and f0110 (prep-touch-fire-and-hop 94c06286, raft R0051) designs. Experiments in a scratch clone of the prototype, specs run singly.

### F1 [high] The Problem is not the captured one, and no Scope decision line records the change
Where: Problem, Non-goals, Solution, title; `./zn capture f0109`.
Evidence: `./zn capture f0109` prints 25e64e3c, "Frightened colors". There, "a frightened ghost blinks white at the end, and the player wants that white to be a different color", and its Non-goals say "The four ordinary body colors stay: Blinky red, Pinky pink, Inky cyan, Clyde orange". The document now says the opposite on both counts: Inky changes, and "The frightened blink stays white". The change is fa35872b ("tracker: f0109 changes the white ghost", 2026-10-19, author Philip Bergen, no co-author line), a backlog edit made while the item was `new`. 2ad5ffe6 then adds the user's 2026-10-25 quote "Having a white ghost doesn't work …". Neither adds a `Scope decision (user, …)` line.
Critique: the evidence points to the user's own rewrite (the blink was a misreading of a cyan ghost the user sees as white), but z-design's rule judges scope against the capture plus decision lines. As it stands, every scope check (step 5, each reviewer, z-raft) finds the captured blink outcome dropped. The author may be tempted to read fa35872b as the capture and carry on. That works today and fails the next check.
Consequences: if the user did mean both changes (Inky and the blink), the blink needs a colour, a Design and a criterion. The current AC2 ("blinking … unchanged") would then be wrong.
Recommendation: escalate to the user: "f0109's capture asked for a new colour for the frightened blink; your edit on 2026-10-19 (fa35872b) changed it to Inky's body, with the blink staying white. Is the blink change dropped?" Record the answer in the Problem as `Scope decision (user, 2026-10-19): "<their words>"`, citing fa35872b. If the blink is still wanted, keep it in scope with its own guess, Design row and criterion.
Lesson: z-design/never-narrow-captured-scope

### F2 [high] AC5 is checked on source text: a MazeView that never repaints the walls green passes it
Where: `acceptance/place.spec.luau` (all three cases); Rules and mutants rows N6, N7, N9, and N8 (`reasoned`).
Evidence: in the scratch clone (prototype + f0109's specs), `lune run tests/run -- tests/acceptance/f0109/place.spec.luau` gives `3 passed` on the prototype, and also `3 passed` on each of two wrong adapters:
- (a) `MazeView.edible` reduced to `model:SetAttribute("Edible", edible)`, which never repaints, so the walls stay blue for the whole power time;
- (b) `paint` computing `View.wallColor(Lit, Lit)`, which ignores `Edible`.
The spec asserts that strings exist (`View.wallColor(`, `function MazeView.edible(`, `"Wall", wallColorOf(`) and that two literals are absent. Any body behind those names passes. Main's case likewise matches the call text and would pass with the call under a dead branch.
Critique: the captured outcome is "During that edible time the walls should be green". No check sees a wall's colour. N8 is in the same class, so its `reasoned` note is right that this spec can't catch it, which is exactly the problem. The tempting fix is more string patterns, which the next wrong body passes again.
Consequences: `@tests/lib/fakeengine` runs an adapter's real source with the real Logic (pickman-test, "Running an adapter's real source"), but today it models no `Vector3`, `Part` properties or `:SetAttribute`, and its contract says it must stay exact in both directions: extending it re-runs f0061's mutants. MazeView requires Logic through `@game/ReplicatedStorage/Shared/Logic/<X>`, which the fake's requirer already resolves. "Built or rebuilt while edible" has no rebuild path in f0109 (only f0126's `rewall`), so that clause stays a source pin here and becomes f0126's behaviour case.
Recommendation: replace the MazeView cases with a behaviour case on MazeView's real source under the fake engine (extend it for `Vector3`, `Part`'s `Color`/`Size`/`Position`/`Anchored`, `Model:SetAttribute`): build the classic maze, then check every `Wall` part's colour through the sequence blue → `edible(true)` green → `flash(true)` white → `flash(false)` green (kills N8) → `edible(false)` blue. Turn mutants (a) and (b) and N8 into `run` rows. Keep Main's source pin; Main is a bootstrap script the fake doesn't run. Record the fake's extension and the f0061 mutant rerun in Unknowns & experiments.
Lesson: z-design/spec-design-correspondence

### F3 [medium] Under G3 the walls stay green while revived ghosts can kill, but only Inky is checked against green: Blinky's contrast on it is 1.05
Where: Design "The walls", G2, G3; `colors.spec` "Inky stands out against the walls, edible or not" (its comment: "an eaten ghost comes back dangerous, in its own colour, while the walls are still green"); AC1, AC3.
Evidence: WCAG contrast against `(0, 152, 0)`, computed with the spec's own formula: Blinky (255,0,0) **1.05**, Clyde 2.23, Pinky 2.47, Inky 3.40, frightened 2.01, floor 5.49. For comparison, Blinky on today's blue wall is 2.25. A grid search over every green-dominant colour (r, b in steps of 8, g in steps of 4) for the best worst-case contrast against all four ghosts and the frightened blue finds only near-black: (0, 4, 0) scores 2.68, and no visible green keeps every ghost at 2 or more.
Critique: the issue exists for visibility ("its new color must stand out from the walls"). The design applies the revived-ghost reasoning to Inky alone. A Blinky that revives, or is shot and revives, before the timer ends is red on green with almost no luminance difference, and players with red-green colour blindness can't see it at all. G2 was put to the user as "a brighter green would wash out Inky and the blue ghosts", without these numbers.
Consequences: no single green fixes it (the search above). The real options trade against things the user decided (G2, G3).
Recommendation: escalate to the user: "With green walls (0,152,0), a revived red Blinky has contrast 1.05 against the walls (Clyde 2.23, Pinky 2.47), and no visible green keeps all ghosts at 2 or more. Options:
- (a) keep G2 and G3 and accept it (the hue still differs, except for red-green colour-blind players);
- (b) the capture's literal reading of G3: blue again the moment any ghost is dangerous (cost: the walls switch back within one power period);
- (c) a darker green, with Blinky at about 2 or more and the frightened blue near 1, so frightened ghosts are hard to see during the very time they're edible;
- (d) keep the green and give revived ghosts an outline or glow during the power time (new scope)."
Then add whatever bar the answer sets for all four ghosts to `colors.spec`, not only Inky's.

### F4 [medium] game-design.md isn't touched: its open question still says Inky's colour is unchosen, and the decisions go unrecorded
Where: Touched modules (no `pickman/.tracker/game-design.md`); game-design.md line 86: "**Inky's colour** (f0109): Inky's body (and, with R0035, its glow) is `(0, 255, 255)`, which the user sees as white; a new colour is wanted but not chosen."
Evidence: the prototype's diff leaves game-design.md as it is. The user's decisions (lemon Inky, green walls while the power timer runs including revived ghosts, the flash wins, gold marked walls stay gold) exist only in this issue. f0110 (R0051, prepared) quotes that line: "game-design.md records that the user sees `(0, 255, 255)` as white (Inky's colour, f0109), so FIRE may look like JUMP's white".
Critique: game-design.md is binding and quoted by later designs. Leaving the open question stale invites the next prep to ask again, and leaves f0126 quoting colours from an issue rather than from the source of truth. f0125 does this step and pins it with a docs spec; f0109 doesn't.
Consequences: the rewrite must keep the fact that the user sees (0,255,255) as white, which f0110's FIRE caption reasoning relies on (the shot colour stays cyan).
Recommendation: add game-design.md to Touched. Move line 86 out of Open questions into a decision ("Inky's colour and the edible walls (f0109, 2026-10-25)": lemon (230,255,0); walls green (0,152,0) while the power timer runs, blink and revived ghosts included; the level-clear flash wins; f0126's marked walls stay gold; the user sees (0,255,255) as white). Add a `docs.spec` case (decision present, open question gone) and a mutant row.
Lesson: z-design/restated-rules-move-together

### F5 [medium] The radar's walls keep their own copy of the wall blue, so "every colour a wall is drawn in lives in View" is false
Where: Design "Maintainability"; `pickman/src/client/DangerHud.luau:119`.
Evidence: `git grep -nE "fromRGB\(|r = [0-9]+, g = [0-9]+, b = [0-9]+" -- src` (in the prototype) lists every colour in `src`. Wall-blue hits: `DangerHud.luau:119 dot(radar, Color3.fromRGB(33, 33, 222), CELL)`, which draws the radar's walls, and `HudView.luau:18 BLUE = (33, 33, 222)`, used at line 126 for a HUD frame, not walls (excluded). MazeView's walls are the only ones that move to `View`.
Critique: the minimap draws the maze's walls. Whether they turn green with the maze is undecided, and as written they stay blue by accident, through a constant `View.WALL_COLOR` doesn't own.
Consequences: if the radar follows, DangerHud needs the edible state (it already receives the snapshot through `DangerHud.push`), and it's another adapter to pin (F2's approach).
Recommendation: put to the user with F3: "Do the radar's walls turn green with the maze?" Either way, DangerHud reads `View.WALL_COLOR` (or `View.wallColor`), and a place or behaviour case pins it. Fix the Maintainability sentence to match.
Lesson: zz-test/one-rule-one-function

### F6 [medium] colors.spec judges Inky's distance against hard-coded copies of the pellet, shot and gold colours
Where: `acceptance/colors.spec.luau:40-43` (`PELLET`, `SHOT`, `GOLD`); AC1.
Evidence: the spec's constants copy `PelletView.luau:10`, `BlastView.luau:14` and `HudView.luau:19` (cyan), and f0126's gold, which isn't in the code yet. If any of those views changes its colour, or f0126 lands a different gold, the distance case still judges the old value and stays green while Inky may now clash.
Critique: AC1 promises distance from "the pellets, the shots and f0126's gold marked walls" as drawn, not as copied on the day of prep. The gold copy is a promise only f0126 can keep.
Consequences: moving those colours into `View` touches three more adapters (scope growth the user hasn't asked for). Reading them from the built place's source keeps f0109's footprint.
Recommendation: read `PelletView`'s and `BlastView`'s `COLOR` from the built place source in `place.spec` (the `Color3.fromRGB(r, g, b)` on the `local COLOR =` line) and feed them to the distance check. Drop `GOLD` from f0109's spec, and have the lead hand f0126 (which lands second, G4) a case asserting its own gold constant is at least 30 from `View.GHOST_COLORS.inky`.

Verdict: changes
