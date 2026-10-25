# Review 002: R0011 (design mode)
Inputs: working tree on a371ed8ca3589d17de1f32afe3353b50100e9256 (R0011, f0024, f0025, f0026, `tracker/architecture.md` uncommitted). Read with `src/server/Sessions.luau`, `src/shared/Logic/Session`, `Game`, `Flow`, `Lobby`, f0065 (design ready), and `tests/lib/fakeengine.luau`. `lune run scripts/affected` on the touched paths matches the lists in the issues; `Overrides: none` is still right (no promoted spec turns red). No spec or `check.sh` writes the repository.
Dropped from review-001: F2, F3. The play-again conflict with f0065 is gone (`sessions.spec` allows zero calls, `flow.spec` never reads `playAgain`, the bit is `banner == "GAME OVER"`). The late-rank sequence review-001 named is now in `flow.spec`.

### F1 [high] A Heartbeat that calls `Session.advance` and then steps once still passes (repeat of review-001 F1)
Where: `tracker/issues/f0025/acceptance/sessions.spec.luau` (the advance case, the `PlayerRemoving` case); `src/server/Sessions.luau:51-57`; `src/shared/Logic/Session/init.luau:106-108`
Evidence: `sessions.spec` counts `Session.advance%b()` as 1 and requires each `Hiscores.onStep` to occur later in the file than the first `Session.advance` text. It does not require a `for` loop, and it does not require `Session.step` or `onStep` to sit inside that loop. This source passes it and still steps once per Heartbeat:

```lua
RunService.Heartbeat:Connect(function(dt)
	Session.advance(clock, dt)
	for player, s in sessions do
		local events = Session.step(s)
		local here = player.Parent ~= nil
		local state, submission = Hiscores.onStep(runs[player], events, here)
		-- submit, and FireClient only under `if here then`
	end
	for _, parked in pending do
		local events = Session.step(parked.session)
		Hiscores.onStep(parked.state, events, false)
	end
end)
```

`STEP_RATE` is 15 and `MAX_STEPS_PER_ADVANCE` is 5. Heartbeat is about four times that, so the maze runs fast and `LEAVE_STEPS` (45) elapses in under a second. A disconnect at the start of the 45-step dying pause (`Game.step` emits `GameOver` on the 45th dying step) is dropped before `GameOver`. The same case treats `PlayerRemoving` as passed when the handler contains the substrings `sessions[player] = nil` and `pending`. An unused local named `pending` passes, and the spec never reads `state.drop`, so the parked session is stepped for the life of the server. `if here then` only has to appear somewhere before the first `Session.frame`; the `FireClient` can sit after that `if`'s `end`.
Critique: Round 1 asked for the step to be textually inside the advance loop. The fix checks that the word `advance` occurs earlier in the file. Another substring (`for _ = 1, Session.advance`, a balanced `end`) fails the same way: a comment-stripped scan cannot see which `end` closes the loop, and the last two rounds are that scan. The tempting fix is a third needle.
Consequences: `advance` returning 0 must not move `waited`. Catch-up is up to five `onStep` calls in one frame; `once` already ignores the extras. A parented `GameOver` must not take the player out of the live map: f0065's `Sessions.isOver` is `sessions[player] ~= nil`, and a player removed at game over cannot be sent to the lobby. A departed player is removed only when `onStep` returns `drop`, after the loop, not during `pairs`. The parked run still has no `Player`. Two runs for one user id remain possible; F2 is what then drops the score.
Recommendation: Stop pinning this with source order. In `sessions.spec`, `luau.load` `src/server/Sessions.luau` under a stub `game` (do not extend `tests/lib/fakeengine.luau`; f0061 pins it and f0065 is about to change it). Count `Session.step`. `dt = 2 / Session.STEP_RATE` steps each live session twice and each parked session twice. A `dt` for which `advance` returns 0 steps nobody and does not `FireClient`. After `Parent` is set nil, further frames do not `FireClient` that player. A `GameOver` while parented leaves the player in the live map. A parked run with no `GameOver` is not stepped on frame 46. `leave.spec` stays the pure 44-then-GameOver case. Do not add `Sessions.isOver`.

### F2 [high] The store's `once` drops every later visit, because every visit is run 1
Where: `tracker/issues/f0024/f0024.md` (`HiscoreStore.submit` calls `once`); `tracker/issues/f0024/acceptance/adapter.spec.luau` (the `Hiscores.once` needle); `tracker/rafts/R0011/R0011.md` (decision 6, the run-policy paragraph); `tracker/issues/f0025/f0025.md` (`newRun` and the rejoin)
Evidence: `newRun()` is `{ run = 1, done = {} }`. A rejoin's Ready, and every later visit, calls `newRun()` again. f0024 says `HiscoreStore.submit` calls `Hiscores.once` for that user id and run, and a second call does not drive. `adapter.spec` requires the source to contain `Hiscores.once`, so the map has to exist. Nothing clears it. `onStep` has already consumed the `RunState` copy, so the store map is a second one, keyed by user id, and it outlives the `Player` (the parked submit runs after `PlayerRemoving`). First `GameOver` on that server records run 1 and drives. The next visit is also run 1, `once` returns false, and `drive` never runs. On a one-server Beta that is the second game onward, including a higher score. The rejoin during the parked window, which the raft says "can submit", loses the same way: both runs are run 1, and whichever `submit` lands second is discarded. `run.spec` only sees the pure `RunState`. No spec drives twice.
Critique: `onStep` already refuses a second `GameOver` for one `RunState`. The store-level `once` does not dedupe that; it dedupes two visits. Keeping it and "fixing" the key (a server-wide counter, `tick`, `os.clock`) is the tempting fix, and it reintroduces a second identity the `RunState` already has. Play again does not save this: `onAgain` reaches run 2, but decision 6 makes the next visit a new `newRun()`, and f0065 deletes the handler.
Consequences: Two `submit`s of the same score are already a no-op through `commit` (the row is equal, so it is not replaced). A worse score is refused by `commit`. A better score must be written. The parked run and the new visit are two `RunState`s and both have to drive; `commit` decides which row stays. There is no third run id.
Recommendation: The process-lifetime `once(userId, run)` cannot represent a counter that resets to 1. Delete it. f0024 says `submit` always `task.spawn`s `drive`. `adapter.spec` forbids `Hiscores.once` in `HiscoreStore.luau` (the needle flips). Deduping stays inside `onStep`'s `done`, which dies with the `RunState`. Rules row: mutant "the adapter rejects run 1 the second time", killed by the forbid and by two fresh `newRun()` values both returning a submission. Do not add a generation counter.

### F3 [high] `scorePage` is specified to copy the packed integer onto the board (repeat of review-001 F5)
Where: `tracker/issues/f0024/f0024.md` (`scorePage` copies `{ key, value }`); `tracker/issues/f0024/acceptance/store.spec.luau` (the `value = 12` case); `tracker/rafts/R0011/R0011.md` (`scorePage` unpacks); `tracker/issues/f0026/acceptance/endtoend.spec.luau`
Evidence: `pack(score, level)` is `score * LEVEL_CAP + min(level, 9999)` with `LEVEL_CAP` 10000, so a score of 50 at level 2 is stored as `500002`. The raft says `scorePage` unpacks `value` into the displayed score before `rows`. f0024 says `scorePage` copies `{ key, value }` to `{ key, score }`, and `store.spec` locks that: an entry `{ key = "4", value = 12 }` must come back as score 12. An unpack (`12 // 10000 == 0`) fails the spec. `rows` displays the page score. `Lobby.lines` prints that number. The implementation that passes `check.sh` shows `500002` in the lobby. `fake().top` returns the unpacked score (`rows.spec` expects `10`), and `endtoend.spec` asserts `50` through that fake, so AC5 stays green while `Boards`, which is specified to feed `GetSortedAsync`'s `value` through `scorePage`, shows the pack. `rankOf` uses the user id, so the overlay's `#n` is right and the panel's score is wrong.
Critique: Packing was the fix for "level order versus one page". The unpack was left as a sentence the sequestered spec contradicts, and during execution the spec wins. The tempting fix is a second conversion inside `rows` or `lines`. `rows` is also given already-unpacked pages by `fake().top` and by the hand-built tie cases; a `rows` that always divides by `LEVEL_CAP` turns those scores into 0.
Consequences: One function is the only place an ordered integer becomes a displayed score. `PageEntry.score` is that score, never the pack. `rows` does not know `LEVEL_CAP`. The packed level is the sort key only; the displayed level stays the companion's, including levels above 9999. A raw `value` of 12 is not a legal stored score (`pack` of a valid attempt is at least `1` and, for any score above 0, at least `LEVEL_CAP`). No second page, no migration.
Recommendation: The pack does not work while `scorePage` is specified as a copy. Change `store.spec` so `{ key = "2", value = Hiscores.pack(10, 7) }` yields score 10, and so a bare `12` is not the contract. Delete the "copies `{ key, value }` to `{ key, score }`" sentence. `fake().top` returns that function's output, not a private unpacked convention. Rules row: mutant "scorePage returns `value` unchanged", killed by the `pack(10, 7)` case. `endtoend.spec` stays on the fake.

### F4 [high] The overlap fake publishes the winner before the loser runs, and it maxes for the caller (repeat of review-001 F4)
Where: `tracker/issues/f0024/acceptance/drive.spec.luau` (the success `updateScore`, the overlap case, the retry case); `tracker/issues/f0024/acceptance/adapter.spec.luau`; `tracker/issues/f0024/f0024.md` (`drive`, the nil-commit rule)
Evidence: The overlap fixture sets `entry = nextEntry` and only then calls the second `drive`. That second `get` therefore sees score 5000. A drive that does `local pre = io.get()` (nil), `commit(pre, attempt)`, and `updateEntry` with `function(_stored) return precomputed end` still passes: the nested loser observes 5000, writes nothing, and every recorded pack is `pack(5000, 2)`. The success fixture hides the other half:

```lua
local kept = math.max(entries[id .. ":packed"] or 0, packed)
```

A later `updateScore(pack(10, 9))` leaves `pack(80, 3)` in the table, which is what that case asserts. `adapter.spec` requires the letters `UpdateAsync` and `Hiscores.pack` and forbids `SetAsync`. It does not require `math.max` or `merge`. This callback passes it and is last-writer-wins:

```lua
ordered:UpdateAsync(key, function(_old)
	return Hiscores.pack(committed.score, committed.level)
end)
```

The race that callback loses, with both transforms otherwise correct: drive A commits 5000 and its ordered write fails; drive B commits 8000 and writes `pack(8000)`; A's retry writes `pack(5000)` because the design retries that same integer and does not read the ordered key again. The board shows 5000. The companion holds 8000, so a later attempt of 6000 does not `qualifies` and never repairs the page. The same hole exists when all three ordered attempts fail and the process keeps the companion: a nil `commit` "does not write the ordered key", so the score never appears.
Critique: A double that applies `commit` to the row it has already stored, and that maxes inside `updateScore`, cannot see a blind write. Round 1's fixture had the same shape (the test double did the policy). Moving the max into a source needle repeats the `SetAsync` miss: the word can be absent from the callback and present in a string.
Consequences: `UpdateAsync` may run the transform more than once and may hand it a value stored by the other drive. The transform does not yield and does not call `get`. A losing attempt still has to repair an ordered key that is behind the companion, or a partial failure is permanent. Day and week stay independent. `GetSortedAsync(false, pageSize)` stays the descending read. Boards stays read-only.
Recommendation: Stop testing this race with a fake that cooperates. `updateScore` takes a transform `(old: number?) -> number?`, the same shape as `updateEntry`. `drive` passes `function(old) return math.max(old or 0, packed) end`. The spec fake stores whatever that function returns and calls it with a higher integer already stored: a retry of `pack(5000, 4)` against stored `pack(8000, 1)` leaves `pack(8000, 1)`. A function that ignores `old` fails that case. Separately, `get` returns the pre-drive snapshot while `updateEntry` calls the transform on the live row: both drives read nil, the live companion ends at 5000, and a transform that returns the pre-read attempt fails. A nil `commit` still runs the ordered transform with `pack` of the companion actually stored, so the exhausted-retry case is repaired by the next attempt of 100. Spec that. Delete "a nil commit does not write the ordered key". The adapter callback is the function `drive` passed, not a second copy the needle has to spell.

### F5 [medium] The entry edge keeps a stale rank whenever a pending run also matches
Where: `tracker/issues/f0026/f0026.md` (`follow` / `hearRank`); `tracker/issues/f0026/acceptance/flow.spec.luau` (the late-rank case); `tracker/rafts/R0011/R0011.md` (the rank paragraph)
Evidence: `hearRank` of `run == over` sets `rank` after dismiss, and `flow.spec` requires that (`shownRank(late, true)` is `ALL-TIME #4`). `follow` on the next edge "clears `rank` unless `pendingRun` equals the new `over`". This implementation passes every case in `flow.spec`, including the early rank at `over == 0` and the late rank with no pending:

```lua
if pendingRun == over then
	if rank == nil then
		rank = pending
	end
else
	rank = nil
	pending, pendingRun = nil, nil
end
```

The sequence the spec does not run: overlay of run 1 dismissed, `hearRank(view, 2, 9)` stores pending, `hearRank(view, 1, 4)` sets `rank` because `over` is still 1, then the edge into run 2 keeps `ALL-TIME #4` because pending matches and `rank` is not nil. That ordering is the retry the design already has (`base` 0.25, then 0.5): run 1's rank is in backoff, run 2's rank is computed and sent, then run 1's packet arrives, then run 2's overlay opens.
Critique: Review-001's conditional clear is the bug again. "Clear unless pending matches" preserves `rank` across the edge, and the late packet's job is to write `rank` after dismiss. The early-rank case only forces a fill when `rank` is nil. The tempting fix is another guard on `hearRank`.
Consequences: On the false→true edge the shown rank is the pending rank or nil, assigned, never the previous `rank`. A packet for the closed run is not stored after the overlay is down; a packet for `over + 1` is the only pending slot; `over + 2` still returns the same table. While the overlay is up, `run == over` still applies. `shownRank` stays nil when the banner is not `GAME OVER`. Pending stays one slot.
Recommendation: The one `rank` field that survives the edge is the wrong model. `hearRank` takes the same banner bit `FlowView` already passes to `shownRank`. When the bit is false, `run == over` returns the same table and does not write `rank`. On false→true, `follow` sets `rank` from pending when `pendingRun` is the new `over`, and otherwise sets `rank` to nil, then clears pending either way. Replace the `shownRank(late, true) == "ALL-TIME #4"` assert: after dismiss, `hearRank` of that run with the bit false is the same table. Spec the mixed order above and expect `ALL-TIME #9`, not `#4`. A rank heard with the bit true still shows. Rules row: mutant "entry keeps `rank` when pending matches".

### F6 [medium] Two `FireClient`s and a second `"all"` do not gate the retry (repeat of review-001 F6)
Where: `tracker/issues/f0026/acceptance/adapters.spec.luau` (the Boards case, the LobbyView case); `tracker/issues/f0026/f0026.md` (Boards, `LobbyView`)
Evidence: `adapters.spec` counts `FireClient` in `Boards.luau` (`fires >= 2`) and requires the substring `failed`. A success path that fires twice, plus the word `failed` in a message, passes, and a nil fetch still sends nothing. The client half counts `FireServer("all")` (`asks >= 2`) and requires the substrings `failed`, `READ_GAP` and `task.delay`, with no requirement that one sit inside the other. This passes and asks forever, including after a healthy board:

```lua
board:FireServer("all")
task.delay(READ_GAP, function()
	board:FireServer("all")
end)
```

`GetSortedAsync`'s budget is the one the design refuses to read (`OrderedList` reports 0) and still spends. One ask a second per lobby player is over `5 + numPlayers * 2` a minute. `read.spec` already locks the pure `lookup` (in flight does not fetch, a nil fetch keeps the cache). It cannot see what `Boards` or `LobbyView` do with that result. `lookup`'s nil rows are also three different outcomes (gap, in flight, failure) that share a return shape; only failure moves `lastFetch`.
Critique: Round 1 asked for the failure branch and the gated retry. The fix counts tokens. A third token (`if failed then` somewhere in the file) is the same pin `sessions.spec` uses for `if ok then`, and it does not wrap the ask.
Consequences: A healthy empty board is cached and is not retried. Waiters share one fetch and each gets one answer when it finishes, not a failure fired at join time. The gap is server-side; the client asks again only after a `failed == true` payload. Day and week stay extra requests. `Starts` does not open a store. The highlight sent with the rows is `rankOf` for that player on that board, or nil when they are absent; the design names the argument and never the value.
Recommendation: Stop pinning these branches with word counts. `luau.load` `Boards` and `LobbyView` in `adapters.spec` under a stub `game` and a stub store, the same shape as F1, without editing `fakeengine`. One nil `GetSortedAsync` still `FireClient`s once with `failed = true` and the previous rows (or `{}`). A second request that arrives while that call is yielded does not call `GetSortedAsync` again and gets one `FireClient` when it returns. `LobbyView`, given a `Board` remote the stub parents before `start`: a payload with `failed == true` produces one more `FireServer("all")` after `READ_GAP`, and a payload with `failed == false` produces none across the same wait. `rankOf` of the requesting user id is the highlight argument, including nil. The pure `read.spec` cases stay as they are.

Verdict: changes
