# Review 001: R0034 (design mode)
Inputs: prep worktree `prep-game-over-to-lobby` at 1a8c8ad plus its uncommitted prep (R0034.md, R0034/check.sh, `experiments/prototype.patch`, `experiments/c0063-narrowing.patch`, f0065.md, f0065/check.sh, `f0065/acceptance/*.spec.luau`, the `tracker/architecture.md` diff); c0064's prep (`prep-lobby-beta-publish`); c0063's prep (`prep-narrow-play-again-specs`, whose `narrowing.patch` is byte-identical to `c0063-narrowing.patch`). I ran the code in a scratch clone with both patches applied: the five f0065 specs pass (42 cases; the document says 43), and the whole suite passes (`lune run tests/run`: 1371 passed, 195 files), which confirms E1's tests. No `REPOSITORY CHANGED` and no tripwire fired.

Mutants I ran myself, against f0065's five specs plus every spec that reads the game place's adapters (f0013, f0018, f0019, f0030, f0031 narrowed, f0054, c0041, f0061 `lobby-adapters`/`lobby-place`, `tests/place/structure`). All of them **survive** (124 passed, 0 failed):
- D1: `local sessions = {}` left inside `Sessions.start()`, which shadows the module-scope table, so `Sessions.isOver` is always false. Selene only warns about shadowing (`shadowing = "warn"`), and the gate runs `selene --quiet`, which exits 0 on a warning.
- D2: `Sessions.isOver` returns `false and Session.isOver(...)`.
- A: Returns reports on `WaitForChild("Snapshot")` instead of `LobbyStatus`.
- G1: FlowView's `LobbyStatus` handler drops the report (`trip` stays nil).
- G2: FlowView stores `configured = true` whatever the server says.
- B: FlowView listens with `toLobby.OnClientEvent` instead of `status.OnClientEvent`.

### F1 [high] `Sessions.isOver` is pinned only by a regex, so a game place where the way back never opens passes every check
Where: f0065 Design "Server" (`Sessions.isOver`); `place.spec :: Returns uses Travel, and Sessions.isOver asks Logic …`; `run.spec` `boot()`; Rules table row "Sessions.isOver asks Logic with the player's own string id" (M27 only).
Evidence: `run.spec` starts Returns with its own lambda (`Session.isOver(s, tostring(p.UserId))`), not the real `Sessions.isOver`. `place.spec` only looks for the text `Session.isOver(x, tostring(y.UserId))` in Sessions. Mutants D1 and D2 pass all f0065 specs, every adapter spec and the lint step. D1 is the edit an executor is most likely to get wrong: the prototype moves `local sessions` from `start()` to module scope, and leaving the old line in place is a one-line slip. In the real game both mutants mean `ToLobby` is always refused. The player sees "TAP TO RETURN TO THE LOBBY", taps, and nothing happens, with no report. AC4 ("Main starts Returns with `Sessions.isOver`, which asks `Session.isOver` with the player's own id") is met as text but not as behaviour.
Critique: the obvious fix is a stricter regex (for example "exactly one `local sessions`"). That is another text needle, and it does not catch D2 or any other wrong body.
Consequences: running the real Sessions source needs the fake server to resolve `Maze` and `Session` (its `LOGIC` map holds only `Travel` and `Lobby`). The spec also needs a handle on the Session that Sessions creates so it can reach game over. That widens the fake, and the fake's header says every widening re-runs f0061's fake-dependent mutants.
Recommendation: add a spec case (in `returns.spec` or a new `sessions.spec`) that loads the **real** `Sessions` source on the fake server over `place.load()`.
- `boot` returns the loaded module, so the spec can pass the real `Sessions.isOver` to a booted `Returns`.
- `fake.server` takes an optional Logic override map, for example `{ Session = spy }`, where `spy` is `setmetatable({ new = recordingNew }, { __index = Session })`, so the spec gets the session object that Sessions created.
- Cases:
  - before `Ready`, `isOver(P1)` is false;
  - after `fire("Ready", P1)` and driving the recorded session to game over with `Session.kill`, `isOver(P1)` is true and `isOver(P2)` (no Ready) is false;
  - after `leave(P1)` it is false;
  - end to end, a real `ToLobby` from P1 reaches the engine once.

Add D1 and D2 to the Rules table as `run`, and say in the fake's header that the game place's Sessions is now served too. Re-run f0061's four E3 mutants.

### F2 [high] Which remote carries the status is never checked: a Returns that reports on `Snapshot` passes AC3 and AC5
Where: `tests/lib/fakeengine.luau` `replicatedStorage()` (`FireClient` records `{ player, args }`, no remote) and `statuses()`; Rules table row "The status goes on `LobbyStatus`" (M35 `"Status"`).
Evidence: M35 is killed only because the game place has no remote called `Status`, so `WaitForChild` fails. The game place also has `Ready`, `Intent`, `Snapshot` and `ToLobby`, and a Returns that fires its reports on any of these passes every case (mutant A, run). On Snapshot, the client's frame handler would receive `("going", true)` as a `Session.Frame` and error on every report; on any other remote, FlowView never hears a report. `run.spec`'s simulated client reads `statuses()`, so it can't tell the difference either.
Critique: the tempting fix is to make `statuses()` filter on `LobbyStatus`. But f0061's promoted specs call `statuses()` for the lobby's `Status` remote and can't be edited.
Consequences: the fake has to record the remote's name without changing what `statuses()` returns for f0061's callers, and the "exact in both directions" rule applies.
Recommendation: record `remote = built.Name` in each `Fired` entry, keep `statuses(player)` as it is, and add `reports(remote, player)`. f0065's specs then use `reports("LobbyStatus", P)` everywhere, and one case asserts that, in a whole trip (request, failure, cool-down, heartbeat), Returns fires nothing on any other remote. Add mutant A (`"Snapshot"`) to the Rules table next to M35, and re-run f0061's fake-dependent mutants.

### F3 [high] FlowView is checked only by source needles; dropping the server's reports, or a full-screen button that stays up during play, passes
Where: f0065 Design "Client"; `place.spec` FlowView cases; AC4 ("FlowView … hears `LobbyStatus`"); Rules table (no row for FlowView storing the report or for the `Continue` button's visibility).
Evidence: mutants G1, G2 and B (run) all pass. With G1 the player never sees RETURNING or "Could not return…", and with G2 Studio and an unconfigured Beta show "TAP TO RETURN" for ever, so AC1's prompts never reach the screen. Reasoned, not run: `catcher.Visible = true` (or `= o.prompt ~= nil`) passes every needle. A transparent, `Active`, full-screen `TextButton` that stays visible during play swallows touches meant for the look and move controls on mobile, which breaks play itself. Nothing checks `Visible`.
Critique: more needles (for example `Visible%s*=%s*o%.tap`) only pin one spelling and still miss a handler wired to the wrong remote.
Consequences: the fake already has `fake.client` (f0061 runs the lobby's `Lobby` view on it). Running FlowView means adding `Flow` (real) to the Logic map, a `ContextActionService` stub that records `BindAction`'s handler and keys, a way to fire `OnClientEvent` on a named remote, `activate(name)`, and the remote's name in `fired` (as in F2). The fake must still reject what it rejects today.
Recommendation: add a client spec that boots the real `FlowView` on `fake.client(place.load())`, with these cases:
- `trip()` is nil before any report;
- after `LobbyStatus("cooling", true)`, `trip()` equals that report, and `("idle", false)` gives `configured = false`;
- a `ToLobby` event on the client changes nothing;
- `show(overlay with tap = false)` leaves `Continue` hidden and `activate("Continue")` fires nothing;
- `show(tap = true)` makes it visible, and one activate fires exactly one `ToLobby` with no arguments;
- the bound handler fires on `Return`/`KeypadEnter` `Begin`, but not on `End` or `Space`, and always returns `Pass`.

Add rows for G1, G2, B and the always-visible button, all `run`.

### F4 [high] Nobody owns setting `LobbyPlaceId` on Beta, and until someone does, Beta loses PLAY AGAIN and ends every run at a dead end
Where: R0034 "Risks & rollback" first bullet; f0065 E6 and O2; c0064.md (prep-lobby-beta-publish) "f0065 coordination"; f0065 Touched modules.
Evidence: c0064 says the game target's `LobbyPlaceId` row is "added by whichever of f0065 or this raft lands second", and its specs deliberately leave the row out. R0034 says "it [c0064], or a follow-up chore, must set `LobbyPlaceId` too". f0065's Touched modules don't include `scripts/lib/beta.luau`, and none of its specs or checks pins the row. Whichever lands second, neither design and no `check.sh` requires the row, so O2 ("tap: you arrive in the lobby") has no owner. Meanwhile, as soon as f0065 lands, every Beta run ends at "The lobby is not set up yet." with no PLAY AGAIN: a regression in what playtesters get today. game-design orders f0065 only "after c0063" and never decided the not-set-up behaviour on Beta.
Critique: "file a follow-up chore later" leaves the gap open. Quietly adding `depends_on: c0064` also fixes nothing unless f0065 then adds the row and a spec for it.
Consequences: if f0065 owns the row, it touches c0064's code and must keep c0064's field-by-field `plan.spec` green; it needs legacy-mode behaviour (no game-place variable, so no lobby is published and the game place must not get a `LobbyPlaceId`); and `tests/runtime/structure.luau` might then assert `≥ 1` only in split mode. If a chore owns it, it must exist before this raft starts, and memory says to ask the user before filing new work.
Recommendation: escalate to the user with two options.
- (a) `depends_on: [..., c0064]`, and f0065 adds the game target's `attributes = { LobbyPlaceId = tonumber(start id) }` in `scripts/lib/beta.luau`. Add `plan` cases: split mode tells the game exactly the start id as a number; legacy mode tells it nothing; the lobby target is unchanged. Add an Overrides check against c0064's specs, and add `scripts/lib/beta.luau` to Touched.
- (b) The user accepts the Beta dead end and approves a named chore, filed now and referenced from R0034's Risks.

Either way, record the user's decision on the Beta regression in R0034's "Decisions relied on".

### F5 [low] O1's shortcut to game over can't be followed
Where: f0065 "Observed", O1.
Evidence: O1 says to "call `Session.kill` three times from the server command bar", but the player's Session sits in the `sessions` table local to the Sessions module, which isn't exported, so the command bar has no handle to pass. An observer can't do this without editing code.
Recommendation: replace it with "let the ghosts catch you three times", or name an exact command-bar snippet that works against the shipped code. If neither is acceptable, drop the shortcut.

### F6 [low] The recorded case count doesn't match a run
Where: f0065 E1 ("The five acceptance specs pass (43 cases)").
Evidence: in the scratch clone, `lune run tests/run -- tracker/issues/f0065/acceptance/*.spec.luau` reports 42 passed.
Recommendation: correct the number, or say which run gave 43.

Verdict: changes
