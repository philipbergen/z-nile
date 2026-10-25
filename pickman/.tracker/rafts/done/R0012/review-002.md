# Review 002: R0012 (code mode)
Inputs: HEAD 59c04cf against origin/main 1facc0e (`scripts/tracker.sh sync --fetch`: synced to 1facc0e). Whole diff `git diff origin/main...HEAD`, and the fix delta `git diff 21b7af3..HEAD` (21b7af3 added review-001): Camera, Controls, DangerHud, HudView, the new `tests/place/touch-adapters.spec.luau`, the three issue logs and Problems, harvest, refute-001 and three lesson files. Ran `scripts/check.sh --full` (GATE PASSED, 72.3s wall) and `scripts/tracker.sh check R0012` (7/7: RC0 gate, f0027, f0028, f0029, `promote-check`, RC1, RC2). The tree was clean after both runs. Mutants ran in a scratch clone under /tmp.
Dropped from review-001: F1, F2, F3, F4, F5, F6, F7 (all resolved, rulings below).

Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` lists the same three `M` entries as round 001 (`f0027/acceptance/track.spec.luau`, `f0028/acceptance/look.spec.luau`, `f0029/acceptance/phone.spec.luau`), the user-authorized type-only amendment. `git diff 21b7af3..HEAD` over those paths is empty, so nothing sequestered changed after review 001. No finding.

Rulings on refute-001:
- F1 (same-frame leak): right. `Camera.holdMouse` sets `lookedThisFrame = true` on every change, and `hold()` calls `onTouch` only when the physical held state changes, so the frame in which the first finger goes down or the last one lifts skips `GetMouseDelta`. I walked the cases: a turn finger that moves and lifts in one frame (`mouseHeld` false, latch true: skipped); a snap tap that begins and ends in one frame (true then false, latch true: skipped, `View.snap` not disturbed); a turn finger lifting while a look finger is still down (no change, `mouseHeld` stays true). The latch still clears after the guard and before `snap == nil`, so f0028 AC3's order holds (f0028 3/3). The deviation from "`holdMouse` does nothing else" is recorded in f0028's log with the scenario. It also covers the begin frame, where a touch landing on the locked mouse could jump it. What happens on the frame after a release under the E6 premise is OC1 question 5.
- F2 (ignored finger): right. `down = next(ids) ~= nil` counts every physical touch, ignored ones included. `ids[input] = nil` runs before `hold()` on an end, so the last lift releases. Recorded in f0027's log. AC2's second-finger cases are unchanged.
- F3 (unpinned dispatch): partly right. The new spec pins `snap = rect`, the called `snapRect()`, `FireServer(effect.intent)` in the turn branch, `onLook(effect.dx, effect.dy)`, `onSnap()` in the snap branch, a single change-guarded `onTouch(held)`, the physical count, the focus reset, the `holdMouse` latch and the touch-only Snap frame. I confirmed it uses plain finds throughout. But the call that runs the hold logic on input is not pinned (F1 below).
- F4 (Studio premises): right. Each issue's Problem has a `Decided with the user (2026-10-21)` line accepting merge on the gates. [PR #102](https://github.com/philipbergen/pickman/pull/102)'s description lists all six questions (E9, E5 with the 180° turn, E6, E7, the fast left-half swipe, backgrounding mid-swipe).
- F5 (desktop Snap frame): right. `s.Visible = UserInputService.TouchEnabled` is set once at creation, and nothing in HudView writes `Visible` on the frame again. `HudView.snapRect` still returns the rect. The decision is recorded in f0029's Problem.
- F6 (comment width): right. The header is rewrapped.
- F7 (lost end): right. `WindowFocusReleased` resets `fingers`, `ids` and the hold. A late `InputChanged` or `InputEnded` for a dropped touch finds no id and returns before `Touch.track` and `hold()`. Reassigning `ids` rebinds the upvalue that `onInput` reads. OC1 question 6 checks the engine side.

### F1 [medium] Nothing pins the `hold()` call in `onInput`, so removing it, which undoes both review-001 F1 and F2 fixes, passes every check
Where: src/client/Controls.luau:115 (`hold()` at the end of `onInput`); tests/place/touch-adapters.spec.luau:63-83.
Evidence: Mutant: delete line 115 (`\t\thold()` after the effects loop). Run in a scratch clone: `lune run tests/run -- tests/acceptance/f0014/place.spec.luau tests/place/touch-adapters.spec.luau tracker/issues/active/f0027/acceptance/place.spec.luau tracker/issues/active/f0028/acceptance/place.spec.luau tracker/issues/active/f0029/acceptance/place.spec.luau` gives `19 passed, 0 failed, 5 spec files`. These are every spec that mentions Controls. The spec's "reports held only on a change" case finds `onTouch(held)` once, inside the change block in the `hold` helper's body, and finds `hold()` only inside the `WindowFocusReleased` handler. With the mutant, `hold()` runs only on focus loss, when `ids` is empty and `held` is already false, so `onTouch` is never called. `mouseHeld` never becomes true, the latch from `holdMouse` never fires, and under the E6 premise every turn-zone swipe and every snap tap moves the view again through `GetMouseDelta`. That is the exact defect review 001 F1 and F2 fixed, and the pins added for them stay green. A second plausible mutant also passes: moving `hold()` above `if phase == "end" then ids[input] = nil end`. The last lift then leaves `held` true until the next touch event, so `mouseHeld` stays set and the desktop mouse look of a touch laptop is dead after any touch.
Critique: The fix moved the held logic into a helper and pinned the helper's body, not the call that runs it on input. That is the second round in which a hole turns up in the same mechanism, source-text pins of Controls (review 001 F3 found the dispatch unpinned). The tempting fix is one more substring, `hold()` counted twice. That still accepts a call before the end-clear, a call inside a branch that only some phases reach, or a call before `Touch.track`.
Consequences: Text pins on Controls grow one anchor per fix and keep missing the next placement mutant. A behavioural pin needs `@tests/lib/fakeengine` to load Controls with `UserInputService` input signals carrying `InputObject`-like tables (`UserInputType`, `Position`), `GuiService:GetInsetArea`, `workspace.CurrentCamera.ViewportSize`, a `Remotes.Intent` and `WindowFocusReleased`. The testing skill requires that extension not to make the fake accept less or more than it does now, so the new members are additive and unused by the lobby specs.
Recommendation: Prefer a behavioural spec (editable, for example `tests/place/controls-touch.spec.luau`) that loads Controls through fakeengine with recording callbacks. It should check that:
- `onTouch` records `true` on the first touch's begin;
- `onTouch` records nothing on a second, ignored touch in the same zone;
- after the tracked touch ends, `onTouch` still records nothing while the ignored touch is down;
- `onTouch` records `false` on the last end;
- `false` is recorded exactly once after a `WindowFocusReleased` with a touch down, and a later end of that touch records nothing;
- a left-half swipe fires `Intent` with `"Left"` and never calls `onLook`;
- a right-half drag calls `onLook(dx, dy)` with the drag's step;
- a touch inside the given snap rect on the right half calls `onSnap` once.

Run the two mutants above, and the round-001 list, against it. If extending fakeengine is too large for this raft, the minimum is a text pin inside `onInput`'s body: `hold()` occurs after the `Touch.track(` call, after the `ids[input] = nil` end-clear, and after the effects loop, at the function's top indent (`\n\t\thold()\n\tend`). Record in f0027's log that it is a placement pin with that known weakness. Either way, add each mutant as a row.
Lesson: testing/pin-call-site-arguments

## Judged criteria (code mode only)
- f0027: none. Its document says "Judged: None."
- f0028: none. Its document says "Judged: None."
- f0029: none. Its document says "Judged: None." OC1 is Observed, for the human, now with the six Studio questions in the PR description by the user's decision.

## Lessons (build, `tracker.sh lessons --when build --full`)
- testing/pin-call-site-arguments: repeated (F1).
- testing/plain-find-for-literals: the new spec passes `plain = true` on every literal find. Clean.
- testing/no-vacuous-pass: each anchor in the new spec is asserted non-nil before it is used. Clean.
- architecture/guard-what-the-engine-sees (added this round): the code now follows it. As a lesson, it is general enough for another raft (any adapter flag that suppresses an engine value), not a restated finding.
- testing/order-pins-anchor-unique-text (added this round): general, not a restated finding.

## Lesson candidates (for the raft lead; this reviewer writes no lesson file)
- testing (a note on pin-call-site-arguments, or its own lesson): when a fix moves logic into a helper, a source pin on the helper's body proves nothing unless the call that runs it on the hot path is pinned too, in its place: after the state it reads is updated. Here `hold()`'s body was pinned, and its call in `onInput` could be deleted or moved above the end-clear with the gate green. Check: for each helper a pin inspects, does some spec fail when its call is removed, or moved before the state it reads is updated?

Verdict: changes
