# Review 001: R0035 (code mode)
Inputs: cc4f78e9 (`git diff origin/main...HEAD`, origin/main 388078ad after `tracker.sh sync --fetch`); R0035.md and check.sh; f0100, f0101, f0102, f0104 documents, check.sh files and acceptance specs. Runs: `scripts/check.sh --full` GATE PASSED (2042 passed, 300 files); `tracker.sh check` f0100, f0101, f0102, f0104 each 6/6 PASS. The sequestration diff is empty. RC2 holds: `src/server`, the place files and the lobby are untouched.

### F1 [high] Nothing runs Controls' key handler, so a wrong handler passes f0104 AC4 and the whole gate
Where: `src/client/Controls.luau:41-80` (`handle`); `tests/place/touch-adapters.spec.luau:114`; `tracker/issues/active/f0104/acceptance/place.spec.luau`
Evidence: the touch-adapters harness loads Controls' real source but stubs `ContextActionService = { BindActionAtPriority = function() end }`, which throws the handler away. f0104's `place.spec` checks only that the text contains `UserInputState.End`, `UserInputState.Cancel`, `View.press(`, `.arrows(` and `.aim(`, plus regexes for the Fire and Jump branches. `hunt.spec` copies the client path (`View.action`, `View.aim`, `Blaster.intent`, `Session.submit`) in the spec and never calls Controls. Each of these mutants keeps every pinned string, so the gate stays green:
- `local down = state == Enum.UserInputState.Begin` becomes `local down = state ~= Enum.UserInputState.Cancel`. A released arrow then stays held, and the view never springs back.
- `held = nextHeld` is dropped. `keys.arrows` is called with the stale table, and the change check fires on every event.
- `elseif Movement.isIntent(action) then` becomes `elseif action and action ~= "Fire" and action ~= "Jump" then`. The arrows then send `"LookUp"` and the other look actions to the server, which is the old arrow-moves behaviour in another form.
- The `if h then` guard is removed, so `Blaster.intent(nil)` is sent before the first snapshot.

AC4 says Controls "hears key-up and cancel, tracks arrows with `View.press`", and a handler that does neither correctly still passes it. The code at cc4f78e9 is right as far as I can tell by reading it. Nothing would catch the regression the next time anyone edits `handle`.
Critique: this is the only adapter in the raft with real branching: four action kinds, three input states, and change detection on the held arrows. The tempting fix is more source regexes in a new place spec. Regexes pin spelling, not behaviour, and every mutant above keeps the spelling.
Consequences: driving the real handler needs the stub to return the handler and an input object with a `KeyCode.Name`. The harness's `enumGroup` already makes `Enum.UserInputState.Begin/End/Cancel` items that compare by identity, and its recording `Intent` remote already exists. `Controls.keys` needs a recording stub of `{ arrows, aim }`, including an `aim` that returns nil. No sequestered file changes.
Recommendation: in `tests/place/touch-adapters.spec.luau` (executor-owned), have the stub's `BindActionAtPriority` store its second argument. Add cases that call it with `(name, state, { KeyCode = { Name = key } })`:
(a) W Begin sends `"Forward"`, and W End sends nothing.
(b) Up Begin sends nothing on the remote and calls `keys.arrows` once with `{ up = true }`. Up End calls it with all false. Up Cancel after Up Begin releases. A repeated Begin with no change does not call `arrows` again.
(c) Left plus Up held gives `{ up = true, left = true }`.
(d) E with `aim` returning `"E"` sends `Blaster.intent("E")`. E with `aim` returning nil sends nothing.
(e) Space sends `Hop.INTENT`.
(f) Every key returns `Sink`.
Check that each mutant above turns a case red.

### F2 [medium] HudView's call to `Hud.shotIcons` has its lives argument unpinned
Where: `src/client/HudView.luau:77`; `tracker/issues/active/f0100/acceptance/place.spec.luau` ("HudView draws the shots with Hud.shotIcons …")
Evidence: the spec checks that `Hud.shotIcons(` appears in HudView and nothing about its arguments. `Hud.shotIcons(l, 0, shownShots)`, which draws the bars over the life discs, passes the gate. So does `Hud.shotIcons(l, shownLives, #shots:GetChildren())`, which never shrinks once `ClearAllChildren` is deferred or reordered. `hud.spec` pins the pure function's lives offset (H1), but not this call site, which is the only place where the offset reaches the screen.
Critique: this repeats testing/pin-call-site-arguments. The tempting fix is a regex on the exact argument text. That would work, but it pins spelling rather than the lives offset.
Consequences: HudView has no running harness yet (touch-adapters keeps only "source pins for one line each" for HudView), so a behavioural spec needs a small stub of `ScreenGui`, `Frame` and `GetChildren`. A text pin is the proportionate step.
Recommendation: add an executor-owned place-spec case (beside the touch-adapters HudView pins) asserting the call `Hud%.shotIcons%(%s*l%s*,%s*math%.max%(%s*shownLives` with `shownShots` as the third argument, and that `lay(` runs in both `HudView.show`'s lives branch and `HudView.shots` (the re-lay on either count changing). A mutant passing 0 for lives must turn it red.
Lesson: testing/pin-call-site-arguments

## Judged criteria (code mode only)
None.

Verdict: changes
