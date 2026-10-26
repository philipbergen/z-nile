# Review 011: f0126 (design mode)
Inputs: prep worktree prep-f0126-colours at d27b2bf3 plus its uncommitted changes (`git diff origin/main`: f0126.md, acceptance/adapters.spec.luau, parts.spec.luau, views.spec.luau, experiments/base.patch, prototype.patch, mutants.py); design-review-010.md and design-refute-010.md; f0109's prep (prep-white-ghost-green-walls f88685c5: f0109.md, its three acceptance specs, and its uncommitted design-review-002.md, verdict changes); proto-f0109 (ee121ddc plus its working tree).
A focused re-review of the change for f0109's prep f88685c5. Nothing approved in round 010 is reopened.
Dropped from design-review-010: F1, F2 (answered in refute 010; the promotion dry run is recorded and I re-ran it below).

Evidence run (in `$TMPDIR/rv011`: a clone of this worktree checked out at dc6c8bf1, with `base.patch` then `prototype.patch` applied, and the current acceptance folder copied to `pickman/.cache/rv/f0126/`):
- `python3 pickman/.tracker/issues/f0126/experiments/mutants.py` (all rows): the hash check against proto-f0109 and f0109's prep specs passed (no refusal); BASELINE **149 passed, 0 failed, 16 spec files**; **135 killed** on an assertion, **7 correct variants (C1 to C7) green**, no SURVIVED, ANCHOR or LOAD ERROR. V7 and V8 are killed by "MazeView leaves the holes open and keeps the rest of the model…"; V9 by "View.wallColor: the flash wins…" (see F3). Rows and runner entries match (`comm` of the two id lists: only C1 to C7, F5c, which shares F5b's row, and R3f, which shares R3e's).
- f0126's 13 files alone: **135 passed, 0 failed**; f0109's three (colors, docs, place): **14 passed, 0 failed**. The clone's `tests/acceptance/f0109/place.spec.luau` is byte-identical to the one in f0109's prep (`cmp`).
- Promotion dry run: the 13 specs copied to `tests/acceptance/f0126`: `stylua --check` exit 0; `selene` 0 errors, 0 warnings; `luau-lsp analyze --base-luaurc=.luaurc --platform=standard` exit 0, no diagnostics.
- Whole pickman suite there (`lune run tests/run`): **1574 passed, 10 failed**: c0150's three pins (`f0101/place`, two of `f0104/keys`; c0150's patch isn't applied in this clone), the prototype's stale f0110 copies (`adapters.spec` 5, `buttons.spec` 1), and `tests/meta/architecture` (this prep's architecture.md isn't in the clone: `View -> Picks`, plus f0146's `Pad` edges). Round 010 saw the same failures. Nothing in f0109's specs, MazeView or views fails.
- CIE76 with the spec's own formula (copied from f0109's `colors.spec`): gold (255,191,0) to lemon Inky 45.4, to blue 188.8, to green (12,74,12) 87.4, to Clyde (255,184,82) **23.6**, to the radar's "you" yellow (255,255,0) 37.6.
- My own mutant, Inky set to f0109's rejected yellow (255,230,0) in View: parts.spec and views.spec give **32 passed, 1 failed**, the new case "the marks' gold stands at least 30…" alone. V9 (gold to 240,250,0) fails both the order case and the new case.
- `grep -rn '"Walls"\|Walls model' src tests` in the clone (excluding f0126's own specs): no hits. Nothing else in the game, the promoted specs or the other preps' prototypes reads a `Walls` sub-model (`grep -rlE '\`Walls\`|Walls model|"Walls"'` over `.worktree/*`: only copies of f0126's own files).
- f0109's place.spec `colourOf` reads the parts named `Wall` among `model:GetChildren()` and only after `MazeView.build`, so f0126's `MarkedWall` parts never reach it. Its pin `'"Wall", wallColorOf('` is in the prototype's MazeView.

### F1 [medium] The gold is 23.6 (CIE76) from Clyde, under the bar f0109 set for this very pair of kinds, and the question is left in a Regression-guard sentence with no decision and no home
Where: Regression guard, the f0109 bullet ("Clyde's orange (255, 184, 82) is 23.6 from the gold: a wall block and a ghost differ in shape and motion, and no check covers that pair; it was reported to the user with this change (2026-10-26)"); `parts.spec` "the marks' gold stands at least 30…"; `View.WALL_MARKED_COLOR`, pinned as numbers in parts.spec and views.spec.
Evidence: I measured 23.6 with the spec's own formula. The doc argues that walls and ghosts differ in shape and motion. f0109's E1 doesn't accept that argument: it measured Inky against "f0126's gold marked walls" and turned down yellow (255,230,0) because it was "only 23.1 from the gold, under the bar (30)". Then f0109 asked f0126 to check the same ghost-against-gold-wall pair at 30 (f0109.md line 90). By that measure, Clyde (23.6) fails just as yellow Inky (23.1) did. The doc records no answer from the user and has no Guess or `Decided with the user` line for it. The gold sits in sequestered specs, so if the user later asks for another gold, the issue must be prepped again after z-ready.
Critique: a colour is a user decision (G1 and G4 were the user's), and this one is waiting on an answer that has nowhere to land. The author is tempted to add Clyde to the CIE case, which turns the spec red today, or to keep the shape-and-motion argument, which f0109's own reasoning rejects.
Consequences: a different gold changes `View.WALL_MARKED_COLOR`, GOLD in parts.spec and views.spec, every mutant whose anchor quotes it (V9), and the HUD's gold pick bar and PICK button if they share the constant. It must also stay at least 30 from Inky, which f0109 asked for, and from the radar's "you" yellow, which the marks never meet on the radar.
Recommendation: escalate to the user before this prep lands. "The marked walls' gold is 23.6 from Clyde's orange, under the bar of 30 that f0109 used to reject yellow for Inky against the same gold:
- (a) keep gold (255,191,0) and accept 23.6 for Clyde (wall blocks and ghosts differ in shape);
- (b) move the gold to (255,215,0): 31.4 from Inky, 33.3 from Clyde, 76.8 from the pellets, 88.7 from the edible green. Every spec's GOLD changes, and the CIE case gains Clyde (all ghosts);
- (c) keep the gold and have f0109 move Clyde, which is outside both issues' scope today."
Record the answer as a `Decided with the user (2026-10-26)` line. For (b) or (c), extend the CIE case to every entry of `View.GHOST_COLORS`, add a mutant for each, and re-run the mutants and the dry run.
Lesson: z-design/quote-other-preps-before-promising

### F2 [low] The changed text still carries the old numbers, and AC5 does not say what its new case checks
Where: E12 ("refuses unless all pass (145 cases, 15 files)", "Mutants V1 to V6 are killed"); AC5 and the AC5 label in check.sh; the test plan's parts.spec line.
Evidence: the runner's baseline is now 149 cases in 16 files, and V7 to V9 are rows. E12's last sentence says 149, but its middle still says 145 and 15. The test plan maps "View.wallColor's order; the gold at least 30 (CIE76) from Inky and the walls' blue and green" to AC5. Neither AC5's text ("…the frame's maze, the walls key, the pick bar and the boon banner are as specified") nor its check.sh label names either case.
Critique: a reader of E12 can't tell which baseline holds. AC5's label doesn't say what its command checks.
Consequences: check.sh is sequestered after z-ready, so it must be fixed now, in prep.
Recommendation: in E12, state the current baseline (149 cases, 16 files) and the V rows (V1 to V9). Add "the walls' colour order and the gold's distance from Inky and the walls" to AC5 and to its check.sh label.
Lesson: z-design/restated-rules-move-together, z-design/spec-design-correspondence

### F3 [low] V9 doesn't show that the new CIE76 case can fail: the exact-gold case kills it first, and the case really guards against f0109's colours moving
Where: Rules and mutants row V9 ("the gold at 240, 250, 0"); `parts.spec` "the marks' gold stands at least 30…".
Evidence: the runner records V9 as "killed: View.wallColor: the flash wins…". That case pins GOLD as exact numbers, so any change to the gold is caught there whatever the CIE case does. The CIE case can fail only when Inky, the blue or the green move. My Inky-to-(255,230,0) mutant (f0109's own rejected candidate, its N10) is killed by the CIE case alone (32 passed, 1 failed above).
Critique: the row claims a kill the CIE case didn't make. Delete the case and V9 is still "killed".
Consequences: none.
Recommendation: change V9's mutant to the one this case guards against, Inky at (255,230,0) in `GHOST_COLORS`, keeping its `parts` spec. Optionally add a second one with the edible green moved near the gold.
Lesson: z-design/spec-design-correspondence

Repository safety: the change adds no command. `mutants.py` now also reads f0109's prep worktree (`open` on its acceptance files) and runs `git diff` on proto-f0109 with extra pathspecs. Both are reads. Its writes stay inside its `$TMPDIR` clone (`inside_clone`). The recut was made in a `$TMPDIR` clone, and I found no new refs.

Scope: the Problem, Solution and Non-goals are untouched by this change (the diff edits Behaviour 9, E4, E6, E12, the Regression guard, the test plan, the Rules table and step 8 only). Every captured outcome keeps its criterion as round 010 found. The removed `adapters.spec` case (a `"Walls"` source pin) is replaced by views.spec's behavioural cases (V7, V8), which is a stronger check.

Lessons pass: I asked each check from `./zn lessons --when design` of the changed sections. Findings carry the lessons that apply. `rerun-skipped-checks-after-edits` is satisfied: I re-ran the dry run and it is clean, but the doc's "Promotion dry run" bullet still cites round 010 and should say it was rerun after this edit (part of F2's sweep). harvest.md has no new lessons since round 010.

Note, not a finding: f0109's prep is in its own review round 002 with verdict changes. That round escalates the green again (its F2) and asks for DangerHud to run on the fake engine (its F1). Either change moves proto-f0109, and then `mutants.py` refuses until the base is recut, as designed. f0126's specs read f0109's colours from View, and C6/C7 show they hold if the green is tuned again.

Lesson candidates (for the lead):
- z-design (new, or a note on quote-other-preps-before-promising): when another prep sets a measurable bar for a pair of kinds (ghost against a gold wall at 30), apply it to every member of each kind, not only the one it named, and put each pair that fails to the user instead of arguing it away. Check: does every colour pair of the kinds the bar covers meet it, or does it have a decided exception?
- z-design/spec-design-correspondence, a note: a mutant recorded against a new case must be killed by that case. When an older, stricter case fails first, the new case's own kill is never shown. Pick the mutant the new case exists for. Check: delete the case: does its row's mutant still die?

Verdict: changes
