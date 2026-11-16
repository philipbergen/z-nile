# Review 006: f0126 (design mode)
Inputs: prep worktree at fd74f284 plus its uncommitted changes (f0126.md, check.sh, acceptance/*.spec.luau (13 files, touch.spec and controls.spec new), experiments/prototype.patch and mutants.py, game-design.md, architecture.md); `./zn capture f0126`; f0110's prep (prep-touch-fire-and-hop at 996f445e plus its uncommitted f0110 acceptance files) and proto-f0110 (dc6c8bf1); c0150's prep (prep-narrow-key-and-hop-pins at 9e6ed65d, its narrowing.patch); f0146's prep (prep-console-gamepad at 92fa588c); d0151 and d0149 as captured. Everything was run in a `$TMPDIR` clone (`$TMPDIR/rv006/repo`: dc6c8bf1 checked out, prototype.patch applied, c0150's narrowing.patch applied, the f0126 and f0110 acceptance folders copied under `pickman/.cache/rv/`), except one read-only run of the prototype worktree's own copies of the 13 specs.
Round 1 of the re-prep (the user's scope decision of 2026-10-25). Design reviews 001 to 005 and their refutes were read; nothing they settled is reopened.

Evidence run:
- The 13 spec files on the prototype (`proto-wall-picks-touch`, its copies identical to the prep's: `diff -q` silent): **130 passed, 0 failed** (closed.spec 2.8 s, eaten.spec 2.0 s).
- pickman's whole suite in the clone (`lune run tests/run`, c0150's narrowing applied, f0110 promoted as in proto-f0110): **1431 passed, 2 failed**: `tests/acceptance/f0110/buttons.spec.luau :: Touch.buttons is the snap, fire and hop rectangles together` and `tests/meta/architecture` "cross-feature requires are declared" (the clone lacks the prep's architecture.md edges; expected). The c0150 pins: 9 passed with `ButtonY` bound.
- f0110's *current* sequestered specs (its prep's uncommitted `acceptance/`, buttons.spec dated 14:20, round 4) plus `tests/place/touch-adapters` on the f0126 prototype: **38 passed, 1 failed**, the same exact-buttons case.
- `mutants.py 'U*'`: U1 to U10 all killed.
- My own mutants (`$TMPDIR/rv006/probe/mut.py`): X1 pick zone before snap: killed; X2 PICK above FIRE: killed; X3 PICK level with JUMP: killed; X6 Controls invents its own pick rectangle: killed; **X4 and X5 survive** (F4).
- A placement probe over f0110's 13 samples with f0110's own radar model (`radarOf`, device insets and band): PICK clears the radar, every HUD block, FIRE, JUMP, the snap control, the bar and the banner on all 13. The same over this issue's 15 screens × 4 insets × 3 bands with f0110's model: no radar overlap. So E9's clearance claim holds. Its x against the screen's half is F5.

### F1 [high] f0110's exact `Touch.buttons` pin turns red, and its chore is neither captured nor in `depends_on`
Where: f0126.md Regression guard, the f0110 Overrides bullet; frontmatter `depends_on`; Implementation step 1.
Evidence: f0110's prep, in its fourth review round, still has `buttons.spec.luau:247` "Touch.buttons is the snap, fire and hop rectangles together", `t.expect(T.buttons(box)).toEqual({ snap = …, fire = …, hop = … })`. Run on the f0126 prototype it fails (38 passed, 1 failed), and with f0110 promoted the full suite fails `tests/acceptance/f0110/buttons.spec.luau` on it. The design's answer is conditional: "If f0110 lands with the exact comparison, a chore narrowing that one case is captured and added to this issue's `depends_on` before z-ready (z-ready refuses an undone dependency)". Nobody owns that step and nothing checks it: z-ready can only refuse a dependency that is already in `depends_on`, and the chore does not exist. If the step is forgotten, f0126's executor meets a red promoted spec it may not edit, and has to stop.
Critique: the zz-review rule for item 4 is that every promoted spec the design turns red is named with its chore in `depends_on`. The spec is not promoted yet, but f0126 depends on f0110 being done, which promotes it. So at f0126's execution it is a promoted spec with no chore. The tempting fix is to leave the paragraph as it is and trust f0110's prep to take the request.
Consequences: if f0110 narrows its own case now, d0149 (which replaces the buttons) gains the same freedom, and f0126's E9 must be rerun on f0110's final prototype. If a chore is used instead, it narrows a spec promoted only moments before, and its own prep must pin the whole narrowed file (zz-test narrowing-pins-the-whole-file), like c0150.
Recommendation: settle it in this prep, one of two ways. (a) f0110's prep is still open: hand it the replacement case (snap, fire and hop pinned field by field, more fields allowed), record the agreement in both documents, and rerun f0110's specs on this prototype. (b) Capture the chore now (`./zn new issue c …`, depends_on f0110), add it to f0126's `depends_on`, and name it on the Overrides line. In both cases Implementation step 1 checks that the case is narrowed (as it does for c0150), and stops if it is not.

### F2 [medium] The controller's Y disagrees with f0146's in-flight prep, and the claim that "f0146 keeps Y for the pick" is in no f0146 document
Where: Behaviour 10 (Controller), Interfaces `View` (`KEYS.ButtonY`), game-design.md Platforms row, AC10.
Evidence: f0146's prep (prep-console-gamepad, 92fa588c) puts every gamepad button in a new `Pad.BUTTONS` table and keeps `View.KEYS` for the keyboard ("Controls binds `Pad.BUTTONS`' key codes beside `View.KEYS`'"; "a new action is one row of `Pad.BUTTONS`"; "f0126 (wall picks) may add a pick action that will want a button"). Its `pad.spec.luau:22` pins `Pad.BUTTONS` exactly (ButtonA, R2, R3, the D-pad), and lines 41 to 43 check that no Pad button is in `View.KEYS`. f0126 puts `ButtonY = "Pick"` in `View.KEYS`, and its sequestered `controls.spec` pins `View.action("ButtonY") == "Pick"`. Both preps also rewrite game-design.md's Platforms row: f0146's text is "Desktop (keyboard and mouse), mobile (touch) and gamepad: every input produces the same intents (f0146)", and f0126's AC10 greps for `**every feature supports all three**`, which f0146's text would remove. f0146's G1 to G8 are still with the user, and none of them sets Y aside.
Critique: no spec turns red in either landing order today, because Y is in neither table's check. But the controller map ends up split across two tables. Moving Y to where f0146 keeps buttons would break f0126's sequestered pin, adding it there would break f0146's exact pin, and the second Platforms edit to land breaks AC10 or loses f0146's text. The tempting fix, deleting the sentence about f0146, leaves the split.
Consequences: whichever home is chosen, the other prep has to change its design and its exact pin before review. If f0126 moves to `Pad.BUTTONS`, it gains `depends_on: f0146` and is ordered after it.
Recommendation: agree on one home with f0146's prep now, record it in both documents, and run both preps' specs on a merged prototype, whichever lands second (z-design run-the-other-rafts-specs, design-the-execution-window). The options: (a) Y stays in `View.KEYS`. f0146's design says so, its no-overlap check stays as it is, and its Platforms text keeps f0126's phrase, or AC10's grep is reworded to text both preps write. (b) `ButtonY = "Pick"` goes in `Pad.BUTTONS`. f0146's exact pin includes it, f0126 depends on f0146, and controls.spec checks `Pad.action("ButtonY")`. In both cases, f0146's prep records Y as the user's choice for the pick (2026-10-25), so that no guess of its own can reuse Y.
Lesson: z-design/run-the-other-rafts-specs

### F3 [medium] d0151 is a recorded dependency missing from `depends_on`, and its unknown fix may change the touch path controls.spec stubs
Where: Problem, "Decided with the user … the touch pick" ("this issue waits for d0151 … Order: d0151, f0110, f0126, d0149"); frontmatter `depends_on: [f0100, f0101, c0150, f0110]`; Unknowns; Implementation step 1.
Evidence: f0110's `depends_on` is `[]` in its prep, so nothing orders d0151 before f0126. d0151's own Solution leaves the cause open: "whether `UserInputService.InputBegan` delivers `UserInputType.Touch` there, whether a GUI or Roblox's own touch handling consumes the touches". controls.spec drives every touch case through exactly that path: `world.began.fire(input, false)` on `UserInputService.InputBegan` (lines 119 to 122 and 155 to 157), with `gameProcessed` false.
Critique: if d0151's fix moves Controls off `InputBegan`, or starts honouring `gameProcessed` where it did not before, f0126's sequestered touch cases test a path that no longer carries touches. They are then either red or vacuous, and the executor may not edit them. The design has no experiment or fallback for this.
Consequences: adding d0151 to `depends_on` orders z-ready correctly. The spec risk remains until d0151's fix is known.
Recommendation: add d0151 to `depends_on`. Add an Unknown (E10) with a pass/fail question: "after d0151 lands, do controls.spec and touch.spec pass on its code, through the input path it fixed?". Its fallback is to re-prep the touch cases before z-ready. Implementation step 1 checks that d0151, f0110 and c0150 are in `done/`, and stops if not.

### F4 [medium] The PICK button's inset and its re-layout are unpinned: two plausible mutants survive
Where: controls.spec "HudView draws the PICK button at Touch.buttons' pick rectangle …"; Rules and mutants U7, U8.
Evidence: the case runs one 844 by 390 screen with no inset and renders once. In the clone: X4, `place(pickButton, Touch.buttons(Hud.layout(sw, sh)).pick, l.textSize)` (the layout without the inset): **6 passed, 0 failed**. X5, the button placed only the first time (`if pickButton.frame.Position == nil`): **6 passed, 0 failed**. These are the same two defects T4f and T5a pinned for the pick bar in rounds 4 and 5.
Critique: a notched phone would draw PICK off its hit rectangle (the fold hit-tests the inset rectangle from `HudView.buttons`), and turning the phone would leave it where it was. Because the frame is drawn only, a finger on the drawn disc would then miss the real button.
Consequences: none beyond the spec; the harness already supports a mutable screen and insets (views.spec's T5a world).
Recommendation: run the case on a screen with a 47-pixel side inset, then turn it (390 by 844 with top and bottom insets, then the inset on the other side), and after each check `Pick` against `Touch.buttons(Hud.layout(w, h, inset)).pick`. Add rows U11 (X4) and U12 (X5). Also add rows for the cases that kill mutants but have none: snap, FIRE and JUMP win over PICK (X1), the clearance case (X2: PICK above FIRE), no pick rectangle means no pick (X6), and a key going up sends nothing.
Lesson: zz-test/pin-call-site-arguments

### F5 [medium] On portrait phones PICK lies in the swipe-to-turn half; the design calls it "the right thumb's row", and game-design.md credits the placement to the user
Where: Usability ("On touch the PICK button sits in the right thumb's row"); Behaviour 10; game-design.md Wall picks, "The pick" ("on touch a PICK button one margin left of FIRE, level with it and its size, added after f0110: user, 2026-10-25").
Evidence: the placement probe over f0110's samples (x range of PICK against the screen's half):
```
390x844 pick x 137..207, half 195      360x800 pick x 109..179, half 180
320x568 pick x  71..141, half 160      480x320 pick x 231..301, half 240
500x900 pick x 241..311, half 250      (landscape 568, 667, 844, 900, 1920 wide: right half)
```
On 320 by 568 and 360 by 800 the button lies wholly in the left (turn) half. `Touch.zone` checks the pick before the halves, so a swipe that starts there sends `Pick` and no turn. A Pick beside a marked wall stops the player for 43 steps. The user's decision was only "PICK button after f0110 (Recommended)" with f0110's mechanism; "one margin left of FIRE, level with it" is the prep's choice (E9), but it is not marked **(prep)**.
Critique: turning is the core touch control, and this costs it a 70 by 70 patch where the thumb swipes on the commonest portrait phones, while the document says the opposite. The tempting fix is to correct the sentence. That leaves the user unaware of a usability cost in a placement they did not choose.
Consequences: moving the button changes touch.spec's place case and E9's clearance sweep. Keeping it needs the user's veto chance and a case that pins how much of the turn half it covers.
Recommendation: mark the placement **(prep)** in game-design.md and the document, and put it to the user with the options and their costs. Left of FIRE (today) costs a patch of the turn half on portrait. Above FIRE or above JUMP where they clear the radar, falling back to left of FIRE, costs the radar on 18 and 24 of 24 screens (E9) and needs a rule. A portrait-only place stacked above JUMP needs a clearance sweep. Whatever is chosen, add a touch.spec case that pins its relation to the turn half on the portrait samples, and correct the Usability sentence.

### F6 [medium] Touch and controller have no Observed criterion, although d0151 shows headless touch specs passing while nothing works on a phone
Where: Acceptance criteria, Observed (OC1 desktop only, OC2 readability only).
Evidence: d0151's Problem: "Nothing responds … although R0012 shipped them … and their headless specs pass". AC11 and AC12 are headless only: Touch's fold, and Controls on a stub `UserInputService` and `ContextActionService`. No criterion has a person tap PICK on a device or press Y on a controller.
Critique: the scope decision is the user's "You need to fix the touch players", and a stub cannot show that a real touch reaches the PICK zone, or that `ButtonY` reaches the `ContextActionService` binding on a real pad. zz-test allows an Observed criterion for exactly this.
Consequences: before f0146 a controller cannot steer, so the controller check steers with the keyboard.
Recommendation: add OC3: on a phone in the Beta place, walk beside a gold wall, tap PICK; the player stops and the bar fills; a swipe during the pick wastes it. Add OC4: in Studio with a gamepad connected, beside a gold wall press Y; the pick starts as with F (steering by keyboard until f0146).

### F7 [medium] Statements the scope change made false are still in the document
Where and Evidence (search: `grep -nE "non-goal|either order|Both landing orders|d66229c4|proto-risky-wall-picks|118 cases|11 files|gamepad button|added after f0126|right thumb|touch has no pick|If f0126 lands after" f0126.md`):
- 40, Non-goals: "a gamepad button (f0146)". This contradicts the scope decision and Behaviour 10, with no "Superseded" note like line 37's.
- 213, Regression guard: "d0149 … will add the touch pick button … until it lands, touch has no pick (this issue's non-goal)". The PICK button is now this issue's, and d0149 turns it into a circle (Behaviour 10).
- 212 and 203 (E8): "in either order" and "Both landing orders". `depends_on: f0110` now allows one order only.
- 215: "On-screen buttons added after f0126 (f0110's fire and hop …)" and "If f0126 lands after them". f0110 now always lands first.
- 194 and 198 (E4): the prototype is "`.worktree/proto-risky-wall-picks`, cut from `origin/main` at d66229c4", with "11 files, 118 cases", while E9, mutants.py (`BASE = "dc6c8bf1"`) and the runs above use proto-wall-picks-touch at dc6c8bf1, 13 files and 130 cases.
- 143 (Usability): "the right thumb's row" (F5).
Critique: an executor reading the Non-goals or the Regression guard finds that the touch and controller pick is excluded, then that AC11 and AC12 require it.
Consequences: none.
Recommendation: rewrite each line to the re-prepped design (line 40 drops "a gamepad button"; line 213 says d0149 replaces this issue's PICK button; E8 and line 215 name the single order; the Unknowns preamble names both prototypes and which base each experiment ran on), then rerun the search.
Lesson: z-design/restated-rules-move-together

### F8 [low] Touched modules and Affected specs predate the touch work
Where: Touched modules; Affected specs.
Evidence: Implementation step 7 adds "its unit cases" to Touch, but `tests/unit/Touch` is not in Touched modules (`ls pickman/tests/unit` lists Touch). Affected specs' "New:" list omits `touch.spec.luau` and `controls.spec.luau`, and does not say that f0110's specs (sequestered or promoted, as it lands first) are affected through `src/shared/Logic/Touch`.
Critique: spend attribution and the affected selection miss the new paths.
Consequences: none.
Recommendation: add `tests/unit/Touch`, list the two new specs and f0110's, and refresh the count from `lune run z-nile/affected -- <the src paths>`.
Lesson: z-design/touched-paths-exist

### F9 [low] The prototype runs are recorded for macOS only
Where: E4, E9.
Evidence: E4 says "(macOS jail)"; neither E4 nor E9 records a Linux run (`z-nile/ci-verify.sh`), which the lesson asks of each platform the specs run on.
Critique: the specs are pure Lune and unlikely to differ, but a Linux difference would surface only in CI after execution.
Consequences: none.
Recommendation: run the 13 files on Linux through `z-nile/ci-verify.sh` from a throwaway branch, and record the result in E9, or record why it is not needed.
Lesson: z-design/prove-specs-pass-on-a-prototype

Verdict: changes
