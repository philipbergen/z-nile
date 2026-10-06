# Review 002: R0034 (design mode)
Inputs: prep worktree `prep-game-over-to-lobby` at dab3e8e plus its uncommitted prep (R0034.md, R0034/check.sh, `experiments/prototype.patch`, `experiments/c0063-narrowing.patch`, f0065.md, f0065/check.sh, the seven `f0065/acceptance/*.spec.luau`, the `tracker/architecture.md` diff), design-review-001 and design-refute-001; c0063 (`tracker/issues/c0063`, its `narrowing.patch` is byte-identical to `c0063-narrowing.patch`) and c0064 (`tracker/issues/c0064`, `tracker/rafts/R0032/experiments/prototype.patch`).
Dropped from design-review-001: F1, F2, F3, F4, F5, F6 (all fixes hold, evidence below).

What I ran, in scratch clones under the session scratchpad (no `REPOSITORY CHANGED`, no tripwire):
- Prototype plus c0063's narrowing: the seven f0065 specs pass (52 cases, as E1 says).
- The same plus c0064's prototype (R0032), i.e. the tree as it will be when this raft starts: c0063's, c0064's and f0065's acceptance specs together pass (108 cases, 14 files), and the whole suite passes (`lune run tests/run`: 1371 passed, 195 files). The patches touch disjoint files and apply in either order. c0064's specs build against fixture projects or merge attributes into the real `default.project.json`, so f0065's `"$attributes": { "LobbyPlaceId": 0 }` and its `tests/runtime/structure.luau` change break none of them (`runtime.spec` still sees the game's structure check pass in the built game place and fail in the lobby).
- Mutant D1 (a second `local sessions` in `Sessions.start`): killed by both `sessions.spec` request cases. Review 001's F1–F3 are now pinned by behaviour (`sessions.spec`, `reports("LobbyStatus", …)`, `client.spec`), F4 is owned by c0064 (its `plan.spec`/`deploy.spec` pin `LobbyPlaceId = 222` in split mode and none in legacy mode) with `c0064` in `depends_on`, and F5/F6 are corrected.

### F1 [medium] Two sequestered source needles, now redundant with behavioural specs, reject correct implementations
Where: `place.spec.luau :: FlowView sends only while the overlay says a tap asks` and `:: Returns uses Travel, and Sessions.isOver asks Logic with the player's own id`; Rules rows M27 and M28.
Evidence: I ran three correct variants of the prototype against the seven specs. Each one passes `client.spec` and `sessions.spec` (the behaviour), and fails one `place.spec` case:
- `FlowView.show` sets `catcher.Visible = o.tap` before `live = o.tap`. The needle `string.match(src, "([%w_]+)%s*=%s*[%w_]+%.tap%f[^%w_]")` then captures `Visible` as "the flag", and `if%s+Visible%s+then …:FireServer%(%)` is not found. Result: `FAIL place.spec :: FlowView sends only while the overlay says a tap asks` (15 passed, 1 failed).
- `ask()` written as `if not live then return end toLobby:FireServer()`. Same failure.
- `Sessions.isOver` written as `local id = tostring(player.UserId); return s ~= nil and Session.isOver(s, id)`. The pattern needs `tostring(x.UserId)` inline in the call, so `FAIL place.spec :: Returns uses Travel, and Sessions.isOver asks Logic …` (51 passed, 1 failed).
These specs are sequestered. An executor who reorders a line or names a local hits a red AC4 that it may not edit, and has to stop and escalate (execute-raft stop conditions). Both needles were the only guard in round 1. They are now duplicated by behaviour: `client.spec :: a tap that is not live sends nothing, even if the button is hit` kills M28, and `sessions.spec`, which runs the real `Sessions`, kills M27 (`Session.isOver(s, number)` finds no member, so it is always false; this is the same failure path as D2).
Critique: the tempting fix is to loosen the regexes (for example, look for any `if <x> then` before `FireServer`). That is still a text needle that one more refactor breaks, and it adds nothing the behavioural specs don't already pin.
Consequences: removing the needle cases re-points M27 and M28 to `sessions.spec` and `client.spec`, which must be re-run as mutants. The remaining needles that have no behavioural twin (`Main.server` `.start(Sessions.isOver)`, M26; `Main.client` `Flow.overlay(x.play, y, FlowView.trip())` and `Camera.setCursor(x.cursor)`, M30/M31) stay as they are, because the fake engine doesn't run either Main. They are also shape-specific: `local trip = FlowView.trip()` passed on fails them. The Design should therefore state those two lines verbatim, so the executor knows the shape is pinned.
Recommendation:
- In `place.spec`, drop the case "FlowView sends only while the overlay says a tap asks".
- In "Returns uses Travel, and Sessions.isOver asks Logic …", keep `function Sessions.isOver(` and drop the `Session.isOver(…tostring(….UserId))` pattern.
- Re-point Rules rows M27 (→ `sessions :: Sessions.isOver is false with no session …`) and M28 (→ `client :: a tap that is not live sends nothing …`), re-run both mutants, and record the results in E4.
- In the Design, say that `Main.server`'s `require("./Returns").start(Sessions.isOver)` and `Main.client`'s `Flow.overlay(frame.play, RULES, FlowView.trip())` / `Camera.setCursor(overlay.cursor)` are pinned verbatim by `place.spec`.

### F2 [low] Nothing pins `BindAction`'s touch-button argument
Where: f0065 Design "Client" (`Flow.CONTINUE_KEYS` bound with ContextActionService); `tests/lib/fakeengine.luau` client `BindAction` (`_touch` ignored); Rules table.
Evidence: I ran it. Changing the prototype's `false` to `true` passes all seven f0065 specs and f0031's narrowed specs (80 passed), because the fake drops the third argument. On a phone the engine would then draw a "PickmanContinue" touch button on screen for the whole run, play included, on top of the tap-anywhere target and the swipe area. O2 checks only that swipes work.
Recommendation: have the fake's `BindAction` record `touch`, add `t.expect(touch).toBe(false)` to `client.spec`'s key case, and add the row (mutant `true`, run). Or, if the spec is left alone, name it in O2 ("no extra on-screen button during play").

Verdict: changes
