# Review 002: f0143 (design mode)
Inputs: prep-speed-boost-escape 8164a2dc (f0143.md, check.sh, harvest.md, acceptance/{boost,session,controls,pick,place}.spec.luau, the z-design/run-the-other-rafts-specs note); design-review-001 (no design-refute-001: the answers are in the documents and the Verification log, which z-design allows); proto-f0143b 6db8b4b2 and proto-f0143-picks e4014cc3, each in a scratch clone with the prep's specs copied in; f0146 at prep-console-gamepad 34bc7730; f0126 and d0151 at origin/main 2f1fdd10; d0149 at capture-d0149-circle-answers; f0125 at prep-player-faster 75c9cb81; `./zn capture f0143`; `./zn lessons --when design`; `lune run z-nile/affected` over the full Touched list (the same 99 specs the document lists).
Dropped from design-review-001: F1, F2, F3, F4, F5, F6, F7, F8, F9, F10

Rulings on round 001 (all fixed, checked on the prototypes):
- F1 fixed: controls.spec runs Controls' real source with a scripted `os.clock`. Rerun here on proto-f0143b: M1 (the `if pair` dropped) fails 4 cases, M2 (touch folds `keyTaps`) 1, M3 (every movement intent folds) 1, B20 (the fold only for the W key) 1; the unmutated tree passes 30/30 over controls, session, boost and place.
- F2 fixed for L3: `Pad.BUTTONS.ButtonL3 = "Boost"`, the `"Boost"` action, AC6, and f0146's §2b and G6 point at f0143. f0146's four acceptance specs (34bc7730) pass on proto-f0143b (17/17). The phase of the L3 send is not pinned (F2 below).
- F3 fixed: AC7 runs only on a tree with f0126, which is sound. f0143 `depends_on` f0126, and z-ready refuses a raft whose member depends on an item outside the raft that isn't in `done/` (z-ready step 14). f0126's prepared design names the `walls.marked`, `"Pick"` and `PickStarted` the case reads. Rerun on proto-f0143-picks: pick.spec passes, and B19 (`config.speed = Boost.speed(distance, …)`, the boost after the cap) fails with `expected 6, got nil`.
- F4 fixed (B23, B24 rows and cases). B12 (the boost block moved above the per-tick limit) rerun here: session.spec fails at line 110, `expected false, got true`.
- F5, F6 (Logic), F7 (decided with the user, B22), F8 (`depends_on` d0151), F9 and F10 are fixed in the documents. F6's adapter side and F8's touch path come back as F3 and F4 below, because the mechanisms are new.

### F1 [high] The user's 2026-10-26 decision "Yes, stick up boosts too" has no decision line, no design, no Touched path, no case and no criterion, and the only issue that can own it is f0143
Where: Problem (the decision lines stop at "Same as W; D-pad yes"); §3 Controls and Gamepad; Touched modules; Test plan; AC3, AC6; OC3; f0146.md (no stick boost at 34bc7730).
Evidence: the left stick's turns never go through Controls. On proto-f0143b, `src/client/Sticks.luau` folds `Pad.steer(steer, x, y)` on `RunService.Heartbeat` and sends the result itself (`if turn then intent:FireServer(turn) end`), with no `Boost.tap`. So a double push up sends `Forward, Forward` and never a boost. `grep -n -i "stick" f0143.md` finds only "the left stick's click" (L3). `Sticks.luau` is not in Touched modules, and no case in controls.spec drives a stick, although its stub already has `sticks`, `heartbeat`, `connected` and `last`, copied from f0146's. The brief says the f0146 stream is adding the stick boost. That can't work there: f0146 lands before f0143 (f0143 `depends_on` f0146), `Logic/Boost` doesn't exist until f0143, and the server answers `"invalid intent"` to `"Boost"` until f0143 lands. Making f0146 depend on f0143 instead would make a cycle with f0143's own `depends_on: [f0146, …]`.
Critique: this is round 001 F2 again, a controller trigger handed between f0143 and f0146, and the same rule of the user's (every feature on keyboard, console and touch) leaves it with no criterion. The tempting fix is a sentence ("f0146 adds the stick's fold"), which can't be built in that order and has no check.
Consequences: the decisions this needs:
- **Owner and Taps.** Sticks is a separate module from Controls, so sharing `keyTaps` with W and the D-pad would need new shared state between them. A third `Taps`, owned by Sticks, needs none, but then W followed by a push up never pairs.
- **What counts as a push.** `Pad.steer` emits `Forward` when the stick engages up from released, and also when an engaged stick moves into the up sector from a side. Does either count?
- **Hysteresis.** A stick wobbling between `STEER_OFF` and `STEER_ON` emits nothing, so it never boosts. That is right, but it is a case.
- **Elsewhere.** game-design.md's boost text, place.spec's documents needles, OC3, the AC3 and AC6 wording, the Touched list and Affected specs all change. f0146's prep has to be told not to add the boost, and to point at f0143 as it does for L3 (z-design/quote-other-preps-before-promising).
Recommendation: question the mechanism, not just this trigger. Write one rule into §3 and into f0146's §2b: **every boost trigger, on every device, is f0143's**, and f0146 only leaves the hooks. Add the user's line to the Problem: `Decided with the user (2026-10-26): "Yes, stick up boosts too"`. Add `pickman/src/client/Sticks.luau` to Touched. Specify the fold: on `turn == "Forward"`, `stickTaps, pair = Boost.tap(stickTaps, os.clock())`, and on a pair also send `Boost.INTENT`. Recommended default: every `Forward` that `Pad.steer` emits counts as a push, and the stick has its own Taps. Put both choices to the user only if prep doubts them.
Add running cases to controls.spec, with Sticks booted on the same stub and stepped by `heartbeat.fire()` at scripted times:
- up, release, up at 0 and 0.2 → `Forward, Forward, Boost`; at 0 and 0.31 → no Boost;
- a stick held up through many heartbeats → one `Forward`, no Boost;
- a wobble between 0.4 and 0.6 → nothing;
- a stick push up and a W within the window → no Boost (if the Taps are separate);
- left, then a rotation into up, then a release and up within the window → whatever the decision says.

Add rows for these mutants: Sticks never folds; Sticks folds every emitted turn; Sticks shares `keyTaps` or `touchTaps`. Run them on the prototype.

### F2 [medium] No input case asserts between the press and the release, so a fold on W's release and an L3 that boosts on the click's release both pass AC3 and AC6
Where: acceptance/controls.spec.luau, the `taps` helper (Begin then End, then assert) and the "left stick's click" case (`fired` read after both phases).
Evidence: on proto-f0143b, each mutant was applied alone and `controls.spec.luau` run:
- L3's send moved from the `Begin` branch to `elseif state == Enum.UserInputState.End and action == "Boost" then intent:FireServer(Boost.INTENT)`: 6 passed, 0 failed.
- The keys' fold moved out of `Begin` into an `End`-phase block (W's Begin sends `Forward`, W's End folds and sends the Boost): 6 passed, 0 failed.

The L3 case's `r[1]` is the Begin call's return value, so it checks the sink but not the send.
Critique: the player feels a boost on release: the window is then measured release to release, and the boost comes a key-hold late. This is the defect pickman-test/assert-between-press-and-release exists for.
Consequences: none beyond the cases. Release must add nothing, including no extra `Forward`.
Recommendation: make `taps` assert after each Begin (the press's `Forward`, and on the pair's second Begin the Boost) and after each End (nothing added). In the L3 case, assert `fired == { Boost.INTENT }` after Begin and unchanged after End. Add both wrong-phase mutants as rows and run them.
Lesson: pickman-test/assert-between-press-and-release

### F3 [medium] The chevron's and the camera's adapters are pinned only by source needles: a HUD that ignores the shots, drops the lives block's offset and never changes colour passes every check
Where: §3 HUD (HudView places `Hud.boostIcon` at `blocks.lives` plus the box, re-laid with the lives, the shots and the screen; yellow, white and grey; hidden before the first frame); §3 Camera; place.spec (`Hud%.boostIcon%(%s*l%s*,`, `Boost.fov(`, `FieldOfView`); AC1 and AC3.
Evidence: on proto-f0143b, HudView changed so the placement is `Hud.boostIcon(l, 0, 0)` at `UDim2.fromOffset(box.x, box.y)` and the colour is always `BOOST_COLORS.ready`. Running `place.spec`, `boost.spec` and `tests/place/hud-shots.spec.luau` gives 16 passed, 0 failed. boost.spec pins the Logic box, but nothing checks that HudView uses it with the counts and the block offset, re-lays it, or colours it. The camera is the same: no case checks which tick Camera passes to `Boost.fov`. Round 001 F5's fix lives in `fov`'s arithmetic, and a camera that passes the frame's tick instead of the shown tick brings the one-step lag back.
Critique: round 001 F6 moved the chevron's place into Logic, but the adapter that applies it has no check. A new on-screen element gets the inset and screen-turn cases its neighbours have (the shot bars have four running cases in hud-shots.spec, none of them sequestered). The tempting fix, more needles, passes the same mutants.
Consequences: a sequestered HudView case needs the hud-shots stub (services, inset area, `lay()` on a resize) in the issue's folder, with a loader that falls back to the real Logic (pickman-test/stub-loaders-fall-back), as controls.spec does.
Recommendation: add a running HudView case to the acceptance specs:
- on a screen with a non-zero side inset, the chevron sits at `blocks.lives + Hud.boostIcon(l, lives, shots)`;
- it moves when the lives change and when the shots change, and again after the screen turns;
- `HudView.boost("ready" | "boosting" | "cooling")` sets the three colours, and the chevron is hidden before the first call.

For the camera, pin the argument: run Camera on a stub and check that `FieldOfView` is the base plus `Boost.fov(boosted, shown)` at the shown tick the hop uses, or at least a needle on that exact call with the hop's `shown` local. Add rows for these mutants: no lives offset, the counts ignored, no colour change, the frame's tick passed to `fov`.
Lesson: pickman-test/new-controls-get-inset-and-turn-cases, zz-test/pin-call-site-arguments

### F4 [medium] The touch trigger's sequestered case drives a touch path that the pending touch work may replace, and d0149 removes swipes without knowing the boost depends on them
Where: E4 and controls.spec (`w.swipe` fires `UserInputService.InputBegan`, `InputChanged` and `InputEnded`); Order & dependencies (d0151); the Guesses' overlaps list (no d0149).
Evidence:
- d0151 (origin/main, `design: draft`) is to find why "Nothing responds" on a phone and fix it "at the cause". Its own Solution lists "whether `UserInputService.InputBegan` delivers `UserInputType.Touch` there" and "whether a GUI or Roblox's own touch handling consumes the touches". If its fix moves Controls onto other events (`TouchStarted` and `TouchMoved`, or a GUI frame's input), controls.spec's swipe case sends nothing that Controls hears. It then fails on a correct f0143, in a sequestered file the executor may not edit.
- d0149 (capture-d0149-circle-answers) replaces swipes with a fixed left circle ("a pull … up … is … W"), and the user's order is "d0151, f0110, f0126, d0149". f0143 also comes after f0126, and nothing orders it against d0149. `grep -n "f0143\|boost"` over d0149.md finds nothing.
- If d0149 lands second, the touch boost (two swipes up) disappears unless its circle folds `touchTaps`, and f0143's promoted swipe case turns red.
- If d0149 lands first, AC3's swipe case can't pass.

Critique: the user's every-feature rule needs a touch boost after d0149 too, and neither document records that. Round 001 F8's answer ("controls.spec's running swipe case, not a source needle, pins the touch fold whatever d0151 changes") assumes the event source stays the same.
Consequences: ordering f0143 against d0149 is a frontmatter edit on d0149, which only its own lead or the coordinator makes. d0149's prep then owns a narrowing of f0143's swipe case, as it already does for f0110's specs.
Recommendation:
- Record the touch-event assumption as an experiment with a pass/fail question and a fallback. The question: does Controls still receive swipes on `UserInputService.InputBegan`, `InputChanged` and `InputEnded` once d0151's design exists? The fallback: re-prep controls.spec's touch stub before z-ready.
- Add d0149 to Order & dependencies: f0143 before d0149. Ask the coordinator to add `f0143` to d0149's `depends_on` and a line to its capture: the left circle's pull up must fold `touchTaps`, so a double pull up boosts, and d0149's narrowing chore covers f0143's swipe case.
- If the user wants d0149 first, escalate to the user: the touch boost's trigger then moves to the circle, and f0143's case is rewritten for it.

Candidate lessons (for the lead to harvest; the reviewer writes none):
- z-design: when the user extends one issue's input map with a new trigger during another issue's prep ("stick up boosts too"), decide which issue owns it from `depends_on` before either stream builds it. The issue that defines the intent owns every trigger for it. A trigger placed in the earlier issue can't reach the later one's intent without a dependency cycle. Check: for each trigger of a new intent, does the issue that adds the trigger land after the intent exists?
- z-design: a sequestered stub that drives an input path (touch events, a stick poll) inherits the input path's pending redesigns (d0151, d0149). Name each pending issue that may change the path, and the fallback. Check: which in-flight issues change the events this stub fires?

Verdict: changes
