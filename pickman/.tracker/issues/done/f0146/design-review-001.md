# Review 001: f0146 (design mode)
Inputs: prep-console-gamepad acdd7e76 (f0146.md, check.sh, acceptance/{pad,flow,place}.spec.luau); prototype proto-f0146 95f005af with the prep's specs copied in (scratch clone); capture 667b6908 (`./zn capture f0146`); f0143 at prep-speed-boost-escape 76b6941e; f0126 at raft-wall-picks e21a49f0; f0110 at prep-touch-fire-and-hop 94c06286 and proto-f0110 a042afce; `./zn lessons --when design --full`.

### F1 [high] AC3's source pins pass a Controls that never passes the continue button on, and a Sticks that inverts the stick
Where: acceptance/place.spec.luau, cases "Controls binds Pad.BUTTONS…" and "Sticks, booted by Main…"; E4; Regression guard (touch-adapters).
Evidence: in the scratch clone of proto-f0146 with the prep's specs, two mutants together: Controls' `if input.KeyCode.Name == Pad.CONTINUE then return Pass` became `if action == Pad.CONTINUE then` (the action `"Jump"` compared with the key name `"ButtonA"`: never true, so ButtonA is always sunk and FlowView never hears it at game over), and Sticks called `Pad.steer(steer, state.Position.X, -state.Position.Y)` (stick up turns `Back`). `lune run tests/run -- …/place.spec.luau …/flow.spec.luau` → `5 passed, 1 failed`, the one failure being the documents case (see F5), so every Controls, Sticks, Camera and flow case passed both mutants. The pins check that the text `ContextActionResult.Pass` and `Pad.CONTINUE` occur, not that the pass is reached for ButtonA; flow.spec runs FlowView alone on the fake client, which E4 says doesn't model priorities or sinks; the only running check of the pass is the touch-adapters case the executor rewrites (not sequestered). Nothing pins the arguments Sticks or Camera give `Pad.steer` and `Pad.look`.
Critique: "ButtonA continues at game over" (G4) and "the left stick steers" (the capture's first outcome) can both be broken by one-token slips that pass AC3.
Consequences: a sequestered running case for Controls needs a stub that records the handler per bound code list (f0126's `controls.spec` stub already does this and falls back for Logic requires) and returns the handler's `ContextActionResult`, so the case can assert `Pass` for ButtonA and `Sink` for every other key and button. For Sticks a stub `UserInputService` with a scripted `GetGamepadState` and a Heartbeat signal the case fires is about 30 lines.
Recommendation: add sequestered running cases: Controls on a stub (ButtonA Begin → fires `Hop.INTENT` and returns `Pass`; ButtonR2, DPadUp, W → `Sink`); Sticks on a stub (Thumbstick1 at (0, 0.9) → `Forward`, (0, −0.9) after release → `Back`, (0.9, 0) → `Right`; disconnected → nothing); and pin Camera's call as `Pad.look(<thumbstick>.X, <thumbstick>.Y, dt)` or run it. Add the two mutants above as rows and run them.
Lesson: zz-test/pin-call-site-arguments

### F2 [high] G7 ("the first controller only; a second controller does nothing") is not what the design builds: every controller's buttons act
Where: G7; §2 Controls, FlowView, LobbyPad; Rules and mutants.
Evidence: Controls binds `Pad.BUTTONS`' key codes through ContextActionService, which delivers them from any gamepad; the prototype's handler (`View.action(input.KeyCode.Name) or Pad.action(input.KeyCode.Name)`) never reads `input.UserInputType`, nor does FlowView's continue, and LobbyPad selects START for any of Gamepad1 to Gamepad8 (`Pad.isPad`). Only Sticks and Camera read `Pad.GAMEPAD`. So a second controller jumps, fires, turns with the D-pad and continues; only its sticks do nothing. No spec case gives a button from `Gamepad2`.
Critique: a user decision unmet, with no criterion that would notice.
Consequences: filtering by `Gamepad1` raises the question of a disconnect: when the first controller disconnects, Roblox may leave the remaining one as `Gamepad2`, and the player can no longer play at all. Controls may not say `Gamepad` (f0027's pin), so the test belongs in `Pad`.
Recommendation: add `Pad.accepts(inputTypeName): boolean` (true for `Pad.GAMEPAD` only) used by Controls for pad buttons (keys unaffected), by FlowView's continue and by LobbyPad, with cases (Gamepad2's ButtonA does nothing in Controls' and FlowView's running cases). Then escalate to the user: (a) Gamepad1 only, as decided (a lone controller left as Gamepad2 after a disconnect does nothing); (b) "the most recently used controller", which keeps one player per screen and survives a disconnect.

### F3 [high] The left stick held near a diagonal emits an intent every frame, alternating sectors, and the `Forward` among them cancels the buffered turn
Where: §1 `Pad.steer` ("Engaged, a tilt of at least STEER_ON into another sector moves to it and emits that intent once"); G2.
Evidence: in the scratch clone, `Pad.steer` fed a 0.9 tilt wobbling ±1° around 135° (up-left) for 12 frames emitted `Forward Left Forward Left Forward Left Forward Left Forward Left Forward Left`. The radial hysteresis (`STEER_ON`/`STEER_OFF`) has no angular counterpart, so the sector flips whenever the dominant axis does. W (`Forward`) cancels a buffered turn (*Desktop keys*, f0104, quoted in the Design), so which turn survives at the junction depends on the last frame's wobble; at Heartbeat rate it also reaches the server's 4 intents a step and gets rate limited.
Critique: a thumb pushing toward a side corridor is often near a diagonal; this loses turns in ordinary play, and no case drives a diagonal.
Consequences: an angular margin makes a deliberate quarter-turn of the stick need a slightly larger sweep, a feel parameter beside `STEER_ON`; it is within G2's "dominant axis" but changes what "dominant" means, so the user should see the number.
Recommendation: add an angular hysteresis: an engaged sector is left for another only when the new axis exceeds the held one by a margin (for example `|new| ≥ |held| + Pad.STEER_SWITCH`, 0.2, or 60° from the held axis instead of 45°), with cases: the wobble above emits once; a sweep from up to left emits `Left` once past the margin; a tie from rest still goes vertical. Add the "no margin" mutant as a row and run it.

### F4 [medium] The boost's controller row (L3) is promised by "whichever of f0143 and f0146 lands second" with no owner, order or check
Where: §2b; G6; Non-goals.
Evidence: §2b: "f0143 (the boost) adds its button (G6)"; G6: "one row of `Pad.BUTTONS` mapped to the boost, in whichever of f0143 and f0146 lands second". Neither issue has `depends_on` on the other, neither has an AC or spec for the row (f0143's design review 001 F2), and `Pad.BUTTONS` maps to `View.Action`s, of which there is no `"Boost"`: the row needs a new action and a Controls branch that sends `Boost.INTENT`, which neither document specifies. Once both land, `DPadUp = "Forward"` also goes through the `Movement.isIntent(action)` branch where f0143's prototype folds the double tap, so a double tap of the D-pad's Up boosts as well, sharing W's taps.
Critique: this issue's Non-goals rightly leave the boost to f0143, but its design text tells an executor to add a row nothing checks.
Recommendation: point §2b and G6 at f0143 as the owner of the row and of the decision about the D-pad's double tap (f0143 then `depends_on` f0146), and drop "whichever lands second" from this document.
Lesson: z-design/design-the-execution-window

### F5 [low] The prototype no longer passes the prep's specs, and E2's "6/6" predates the spec change
Where: E2.
Evidence: proto-f0146 (95f005af) with the prep's current specs: `check.sh` → `3/6`; AC3, AC4 and AC5 fail on place.spec's documents case (`game-design.md lacks: | Platforms | Desktop (keyboard and mouse), mobile (touch) and gamepad: every input produces the same intents, and every feature supports keyboard, console and touch`). The row's wording changed with the user's every-feature rule (307137b1), after the prototype.
Critique: the record claims a pass the current specs don't have; the cause is only the prototype's document, but the lesson asks for a rerun after every spec change.
Recommendation: update the prototype's `game-design.md` row, rerun `check.sh` and the mutants, and record the rerun in E2.
Lesson: z-design/prove-specs-pass-on-a-prototype

### F6 [low] LobbyPad never selects START again once the selection is cleared while a controller is in use
Where: §2 LobbyPad; E3.
Evidence: LobbyPad selects START at start and on `LastInputTypeChanged`, only when `SelectedObject == nil`. Roblox's gamepad navigation clears the selection on ButtonB; the last input type stays a gamepad, so nothing re-selects, and the player is left with no selection (Roblox's own ButtonSelect toggles it back, which the design doesn't mention and OC1 doesn't try).
Critique: a likely dead end in the lobby for a console player, unseen by the source pins and by OC1's script.
Recommendation: also re-select START when `GuiService.SelectedObject` changes to nil while the last input is the controller (`GuiService:GetPropertyChangedSignal("SelectedObject")`), with a pin beside the others, and add "press B, then the D-pad" to OC1. If B should leave the lobby's selection, record that and the way back in game-design.md's Gamepad paragraph.

Verdict: changes
