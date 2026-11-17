# Review 001: R0118 (code mode)
Inputs: layer R0118/1/f0145 at HEAD c6e096d0cd22ac028c2a502f697d7a0c9e63981e, diff `git diff origin/main...HEAD` (origin/main 0f5b49026, after `./zn sync --fetch`); f0145.md, f0145's check.sh and acceptance specs, experiments/mutants.py; R0118.md and its check.sh.

Run by the reviewer: `z-nile/check.sh --affected` passed (format, lint, both type passes, both builds; pickman 1967 passed, 0 failed, 275 spec files; no other project affected; no tripwire). `./zn check f0145` passed 8/8.

Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` lists one line, `A pickman/.tracker/issues/active/f0145/acceptance/watch.txt`. That file is the one `./zn finish` generates (zz-review lesson finish-watch-is-generated). Its 20 paths are exactly the 20 `pickman/src` files this layer changes. No spec and no check.sh changed.

Probes: a scratch spec, `pickman/.cache/review-r0118/probe.spec.luau`, made of adapters.spec's stub harness (its first 462 lines) and the cases below. It ran with `../zn run --time 120 -- lune run tests/run -- .cache/review-r0118/probe.spec.luau` from `pickman/` and was removed afterwards.

### F1 [high] On a live server whose arrival write failed, the continue offer says "TEST: NOTHING IS CHARGED" and CONTINUE opens Roblox's real purchase screen
Where: pickman/src/server/Continues.luau:78-86 (`arrive` tells only `if record then`), :126-146 (`useOne` tells only on a continue), :190-199 (`heard` never tells); pickman/src/client/OfferView.luau:19 and :58/:120 (`Flow.offerPrice(nil)`).
Evidence: probe "live mode: an arrival whose write failed never tells the mode", run as `arena("live", 50, failWrites = true)`, then the store works again and the player asks. Output: `PayStatus messages after arrival: 0 offering true` / `after ask: prompts 1 PayStatus messages 0` / `the client's price line with no report: 1 ROBUX (TEST: NOTHING IS CHARGED)`. The design keeps a player whose arrival write fails in play (G10), so a live player reaches the offer while their client has heard nothing. OfferView then shows the line Flow gives a missing report (§4: test mode "or before the server has said anything"), and a press prompts the real Developer Product. A second, milder stale line, from probe "a continue granted after the offer is not told": `PayStatus before 1 after grant 1 last continues 0 stored 1`. A grant that reaches this server outside the offer, or a flight that finds none, never updates the line, so a later offer in the same run says "1 ROBUX" while a continue is held (rule F3, "a held continue shows as held"). §5 says Continues "tells the player the mode and the continues held on PayStatus". The code does so only on the success paths.
Critique: the screen says nothing is charged on the one kind of server that charges. That is a wrong result in the money path, and it happens on a fail-safe the design keeps on purpose. Roblox's own dialog still shows the price, but our screen contradicts it. The tempting fix is to change `Flow.offerPrice(nil)` to the live price. That reverses a pinned, sequestered rule (views.spec: "test mode and no report say nothing is charged") and would make Studio say "1 ROBUX" before its report.
Consequences: if Continues tells on every path, the client needs a status even when the record is unknown. OfferView already reads a non-table status as `held = 0`, so `FireClient(player, Purchases.mode(), nil)` gives "1 ROBUX" live, "STORE UNAVAILABLE" closed and the test line in test. Telling after every write and heard grant adds one small message per purchase or continue. That matches §Scalability's "after each change". The mode is read at each call, so a mode changed after the arrival stays stale until the next tell. Telling on each ask (no store call) bounds that.
Recommendation: in Continues, tell the mode on every "play" verdict, with `nil` status when the arrival write failed. Tell again after every record this server writes or hears: the flight's record (continued or not), the refund, and a heard grant. Purchases.start's callback already passes the `record`, and the test confirm returns it. No sequestered file changes. Add the cases in a spec of your own (not the sequestered adapters.spec):
- a live arrival with a failing write sends PayStatus "live" before any offer;
- a closed one sends "closed";
- a continue receipt heard after the offer sends `continues = 1`;
- a flight that finds none sends `continues = 0`.

### F2 [high] A Studio play-test of the game place is kicked ("Start a game from the lobby.") on every play after the first in an hour
Where: pickman/src/server/Continues.luau:53-68 and :81-89 (a "buy" arrival without a pass is refused and sent back; a failed teleport or an unset LobbyPlaceId kicks); f0145 G1 ("Test mode covers Studio"), E1, G10; OC1 "(Studio, or the Beta experience, test mode)".
Evidence: probe "test mode, a second direct play within the hour where teleports fail (Studio)". It used `arrive("test")` with a stored record whose free start was 600 s earlier, no plays, and `failTeleport` (Studio cannot teleport). Output: `test mode second direct arrival: kicks 1 Start a game from the lobby. over true`. With LobbyPlaceId unset: `kicks 1`. The usual developer loop opens the game place in Studio (Rojo) and presses Play. With Studio API access on (the hiscore boards need it), Studio's first play takes the free start in `PaidPlayTest`. Every Studio play in the next hour is then a "buy" arrival with no lobby pass (Studio's MemoryStore is readable), so its run is refused and the developer is kicked within a second. Before this layer, every Studio play of the game place worked. The capture's playtest outcome says a playtest "will show the screen and accept controls, but not actually deduct". OC1's Studio leg cannot run either, because Studio cannot teleport from the lobby to the game place. The design and its reviews never mention a direct Studio play.
Critique: this regresses the developer's play-test loop. Every sequestered send-back case runs in live mode (adapters.spec:783, :796, :809, :853, :859), so no gate sees it. Two quick fixes are tempting: let test-mode "buy" arrivals play, or special-case `RunService:IsStudio()`. Both change a user decision (G10, "any other 'buy' arrival (a direct join, a friend's server) is sent back"), so the author must not pick one.
Consequences: letting test mode play means Beta direct-joins also play free test games without limit (test records only; nothing is charged either way). An IsStudio branch is one more engine read the stub specs must pin. Keeping today's behaviour makes Studio API access and the Studio play-test exclusive within each hour.
Recommendation: escalate to the user (zz-execute stop conditions) with these options:
- (a) In test mode a "buy" arrival plays, or opens the test purchase screen in place instead of sending back. Cost: Beta direct-joins get free test games.
- (b) Only in Studio (`RunService:IsStudio()`) a "buy" arrival plays. Cost: a Studio-only branch, pinned with a stubbed `IsStudio`.
- (c) Keep it, and say in game-design.md and OC1 that a Studio play of the game place is kicked after its first game each hour while API access is on.

Options (a) and (b) leave every sequestered case green, because they all use live mode (confirm by running `./zn check f0145`). Each option needs a case where a test-mode (or IsStudio) "buy" arrival with failing teleports plays and is not kicked, and the live send-back cases stay as they are.

### F3 [medium] In test mode a confirm whose grant write fails leaves the offer held for good: the countdown freezes and CONTINUE does nothing
Where: pickman/src/server/Continues.luau:201-206 (a confirm acts only `if record and fresh`); pickman/src/shared/Purchases.luau:88-94 (`testGrant` clears the pending screen, then returns `nil, false` for a failed write, the same answer as for no screen at all); pickman/src/shared/TestPurchase.luau:72-76 (the client closes its screen on BUY).
Evidence: probe "test mode: a confirm whose write fails leaves the countdown held", run as `arena("test", 50)`: ask (the test screen opens), `failWrites = true`, confirm, then 600 steps (40 s). Output: `after confirm with failed write: offering true holding true timer 50 was 50`. After the store recovered and the clock moved 10 s, an ask gave `a later ask: test screens sent 0`, because an ask while held is dropped. The run then stays in a frozen CONTINUE? until the player presses END GAME or leaves. Live mode is bounded: a bought close waits at most `RECEIPT_WAIT_TICKS`, and an unbought close releases. A Studio session with API access off fails every write, so OC1's continue would always freeze there.
Critique: the hold an ask sets in test mode has no end once the screen has answered. That is the case the lesson's "No close at all" note covers. The tempting fix is to release on every confirm that grants nothing. That would let a stray confirm (no screen open) release a hold someone else set, such as a flight's hold or a receipt being awaited (rule Q6, "a flight releases only a hold it set").
Consequences: the handler must tell "this confirm consumed an open screen but its write failed" apart from "no screen was open". For example, `testGrant` could return whether it consumed a pending screen, or the handler could note `pending` first. A confirm that consumed the screen and granted nothing is treated as a cancel. The lobby holds nothing, so it needs no change.
Recommendation: in Continues' Purchase handler, release the countdown (as `cancel` does) when the confirm consumed this player's open test screen and the grant came back `nil`. Leave every other hold alone. Cases in a spec of your own:
- test mode, ask, failing write, confirm: the countdown runs on the next step, and a later ask opens the test screen again;
- a confirm with no screen open during a continue's flight leaves the flight's hold;
- a confirm with no screen open while a receipt is awaited leaves that hold.
Lesson: pickman-arch/purchase-close-before-receipt

## Judged criteria (code mode only)
f0145 has no Judged criteria ("### Judged: None."), so there is nothing to rule on. OC1 and OC2 are Observed, run by hand after the merge, and are not judged here. F2 notes that OC1's Studio leg cannot run as written.

Other checks, no finding:
- Logic stays pure, and the one new edge `Lobby -> Pay` is declared (AC8 green).
- `Session.continue` resets as a death's respawn: `teleport` plus `resetGhosts("respawn")`, no `freshMaze`. `bonanza` cannot be set at a death, since it is set only in the step that clears the level.
- `Session.depart` ends a departed run's offer within `LEAVE_STEPS`.
- `ProcessReceipt` grants inside the transform and answers PurchaseGranted only after the write.
- Remotes are made at run time, and FlowView and LobbyView are unchanged.
- No per-frame work beyond one comparison and OfferView's label text.
- No spec or script in the diff touches the repository. `experiments/mutants.py` is a hand-run experiment, recorded as run under `./zn run --time 3000`.

Candidate lessons (for the raft's lead):
- pickman-arch: an adapter that tells a client the mode tells it on every path that lets the player play, the store-failure fail-safes included. A client default that reads "nothing is charged" is never left showing on a live server. Check: for each fail-safe that lets a player through, what does the client's price line say there? (F1)
- z-design: a rule that sends a direct join away names what it does in Studio, where teleports fail and a developer plays the place directly. Check: what does a Studio Play of this place do on its second run? (F2)
- The executor's mutation-runner fix (a green baseline before any row, verdicts computed instead of read by eye, the acceptance folder found by lifecycle) is a lesson candidate for z-design's mutation step: a runner whose specs fail to load reads as all-killed.

Verdict: changes
