# Review 001: f0145 (design mode)
Inputs: prep head d518cc12 (f0145.md with G1-G12 decided; check.sh and acceptance/ as of 0a0534d0), prototype proto-f0145 97ae1e0f. Evidence was run on a `git archive` copy of the prototype with the prep's sequestered specs copied in (scratchpad, its own `git init`); no file in the repository was changed. On that copy: pickman's suite `lune run tests/run` 1417 passed, 0 failed (so `Overrides: none` holds for the prototype); `adapters.spec` 15/15.

### F1 [high] A player who leaves during the last death or the continue offer loses their hiscore
Where: §2 (the offer), §5 (Continues), Regression guard; `Hiscores.leave` / `LEAVE_STEPS` (45) and `Sessions`' parked runs (c0129)
Evidence: a departed player's run is kept only `Hiscores.LEAVE_STEPS` = 45 steps, sized for "the classic dying pause". With the offer on, the last life's pause is followed by 150 offer steps (or a held offer, forever), so the run is dropped before its GameOver. Probe (Session + `Hiscores.onStep`, the player leaving at the third death):
```
offer false submitted true  dropped after steps away 45 phase gameover
offer true  submitted false dropped after steps away 45 phase offer
```
Closing the game at the CONTINUE? screen is the natural way to say no, and a server shutdown kicks everyone the same way, so every such run's score is never submitted. Today the same leave submits. No promoted spec sees it because they run `GAME_CONFIG` with no offer; no f0145 case leaves during the offer.
Critique: the tempting fix is to raise `LEAVE_STEPS` past the offer, which keeps a held offer (purchase screen open when they left) parked forever and still loses the score.
Consequences: ending the offer on leave has to cover the case where the player leaves during the last life's *dying* pause, when no offer is open yet and `decline` does nothing. It also has to get the session before `Sessions`' own `PlayerRemoving` handler drops it (Continues connects after Sessions, so `sessionOf(player)` is already nil there). A continue receipt that arrives after the leave stays a held credit (G9).
Recommendation: when a player leaves, switch their run's offer off and close any open one in the same place that parks the session: in `Sessions`' `PlayerRemoving`, before parking, `Session.allowOffer(s, id, 0)` then `Session.decline(s, id)`. Or add a pure `Session.leave` that does both. Both are no-ops without an offer, so f0025 and c0129 stay unchanged. Add cases, run end-to-end through `Sessions` and `Submits` on the stub: leave during the last dying pause, during an open offer, and during a held offer. Each must submit exactly once within `LEAVE_STEPS`, carrying the lives lost. Add a Rules and mutants row for each.

### F2 [high] A purchase that closes before its receipt arrives ends the run the player just paid to continue
Where: §5 Continues ("Roblox's `PromptProductPurchaseFinished` ... releases the countdown"); E2; prototype `Continues.luau` ignores the event's `isPurchased` (`_: boolean`)
Evidence: Roblox does not promise that `ProcessReceipt` runs before `PromptProductPurchaseFinished`. Receipts are processed asynchronously and retried, and here each one costs two `UpdateAsync` calls. On the stub, the player asks with 3 steps left, the screen finishes with `bought = true`, 5 steps pass, and then the receipt arrives:
```
PROBE over before receipt: true
PROBE receipt: ProductPurchaseDecision.PurchaseGranted
PROBE offering: false over: true held continues: 1
```
The player paid for a continue of this run and got GAME OVER. The adapters case "a receipt continues; a closed screen releases" only covers the receipt arriving while plenty of countdown is left (50 steps). E2 does not list the order of the two events as an unknown.
Critique: the tempting fix is to never release on `Finished`, which holds the offer forever when the purchase is cancelled or the receipt's write fails (`NotProcessedYet`, retried in a later session).
Consequences: this adds a new state, "bought, waiting for the receipt", which needs a bound. When the bound runs out, the countdown resumes and the continue stays a credit (G9). That wait must also end on leave (F1).
Recommendation: release on `Finished` only when `isPurchased` is false. When it is true, keep the hold until the grant continues the run or a bound runs out (a Logic constant, for example `Game.RECEIPT_WAIT_TICKS`, 30 s), then resume the countdown. Add E2's ordering to Unknowns with this as its fallback. Add these cases: finished(true) with 1 step left followed by a late receipt (it continues); finished(true) with no receipt (it resumes after the bound); finished(false) (it resumes at once). Add Rules and mutants rows for "release on any finish" and "never resume".

### F3 [high] A client can grant itself plays and continues with an unsolicited test "confirm"; the credits share the live store
Where: §5 Purchases `testGrant`, lobby `Paid`, game place `Continues`; "Authority and what a client could lie about"; adapters :: "a test confirmation grants a play and starts at once"
Evidence: neither place checks that it opened a test screen before honouring `"confirm"`. On the stub (test mode), five `Purchase "confirm"` with no screen open:
```
PROBE banked continues: 5     (game place, after the offer ended)
PROBE banked plays: 5 teleports 1   (lobby)
```
The sequestered case itself fires `confirm` with no screen open and expects a grant. Every credit is written to the same `PaidPlay` store and keyed the same way in test and live mode. "Test" is any server whose `PaidPlay` is not exactly "live" (G1), which includes a production experience before its publisher sets the attribute. Credits banked there become real free games and continues once it goes live.
Critique: the tempting fix is a pending-screen flag alone. That stops spamming, but it still lets test-mode credits (one per screen the player opens) cross into live.
Consequences: the server now holds "a test screen is open for this player and product" state. It must be cleared on confirm, on cancel, on leave and when the offer ends (a confirm after the offer becomes a credit only if the screen was opened during it). Separate stores per mode mean a switch to live starts everyone fresh, with a free game due.
Recommendation: (a) honour `"confirm"` only for the product of a test screen this server opened for this player, and clear that state on every exit above. (b) Keep the modes apart: `Pay.store(mode)`, with `"PaidPlay"` for live and a different name (for example `"PaidPlayTest"`) for test, so test grants and the test free hour never reach a live record. Rewrite the lobby case so it opens the screen before confirming. Add these cases: a confirm with no screen grants nothing (lobby and game place); a confirm after cancel grants nothing; a test-mode grant is not visible to a live-mode read. Update the stub's `assert(name == Pay.STORE)`.

### F4 [high] AC5's "a forged confirm in live mode grants nothing" is pinned only in the lobby; a game place that grants it passes
Where: Authority section ("A forged `"confirm"` in live mode grants nothing (AC5)"); adapters.spec
Evidence: mutant in the prototype's `Continues.luau`: `Purchases.testGrant(player, "continue", guid)` → `Purchases.grant(player.UserId, "continue", "test:" .. guid)`. Result: `15 passed, 0 failed` on adapters.spec. A live client can then fire `confirm` during the offer and continue for free.
Critique: this is the one place in live mode where a client message leads to a credit, and nothing checks it.
Consequences: none beyond the case.
Recommendation: add a game-place case: in live mode, during the offer and with none held, `Purchase "confirm"` grants nothing and does not continue, and the record's continues stay 0. Add its row (mutant: Continues grants without the mode check).

### F5 [high] Receipt idempotency is not pinned: a read-then-write grant (not inside the UpdateAsync transform) passes every spec
Where: §1 ("a grant records its receipt id in the same write that adds the credit"); E2; adapters.spec's stub `UpdateAsync` (calls the transform once, with the current value, from one thread)
Evidence: mutant in the prototype's `Purchases.update`: compute `change(Pay.record(store:GetAsync(key)))` first, then `UpdateAsync(key, function() return nextR end)`, which ignores the old value. Result: adapters + pay specs `27 passed, 0 failed`. This is the double grant the design's central purchase rule exists to prevent. It happens when a receipt is retried on another server while the first call is still writing (a player leaving the lobby mid-receipt and arriving in the game place), and also for two servers charging an arrival.
Critique: the fixture can't tell an atomic transform from a blind write, because nothing else writes between the read and the write.
Consequences: the stub must model what `UpdateAsync` really does: it may call the transform more than once, with a newer value each time. The adapter then has to take its answer from the last call (the prototype already does).
Recommendation: make the stub's `UpdateAsync` able to (1) write a competing value (the same receipt id already granted, or a free start already taken) just before calling the transform, and (2) call the transform twice, the first time with a stale value. Add cases: a receipt granted by another server during this one's write counts once and is not handed on as fresh; an arrival racing another server's free start uses a held play, not a second free start. Add rows for "blind write" and "answer from the first transform call".

### F6 [high] A player who reaches the game place without the lobby plays free (E1 unverified, and its cheap fallback not taken)
Where: §5 game place ("a player who arrives with neither, after a race with another server, plays all the same"); E1
Evidence: the only check before a game is the lobby's read. The arrival answers `"buy"` and lets the player play. E1 relies on a Roblox setting it calls "off by default", checked only against docs and never run. Joining a friend's public game-place server (the lobby teleports with `TeleportAsync` to the place, not to a reserved server) is a path E1 doesn't mention. The "race" the rule allows for barely exists: the same account can't be in two servers at once, and the lobby spends nothing. So the rule mostly lets in bypasses.
Critique: the tempting fix is to leave it as it is and trust the setting. The game charges real money, the assumption is unproven, and the fallback is one branch.
Consequences: a lobby store that could not be read (G10 lets the player go) followed by an arrival whose write succeeds and answers `"buy"` would send that player back. G10 (decided) says "a store that cannot be read or written lets the player in". The arrival's write did succeed, so the bounce is arguably within G10, but the author should put that reading to the user in the same batch rather than assume it.
Recommendation: make E1's fallback the design. An arrival whose `Pay.start` answers `"buy"` (and whose write succeeded) is sent back to the lobby (`Returns`' teleport) and no offer is switched on. A failed write still plays (G10). Add cases: buy → sent back with the offer off; a failed write → plays. Add a row (mutant: "buy plays"). Put the lobby-read-failed reading of G10 to the user.

### F7 [high] The lives never reach the stored hiscore if the adapters drop them, and AC3 still passes
Where: §3 ("the store adapter passes the submission's lives through (`HiscoreStore.submit(..., lives)`)"); AC3; lives.spec tests Logic only
Evidence: mutants in the prototype: `Submits` drops its sixth argument, and `HiscoreStore.submit` builds the attempt without `lives`. Every f0145 spec except top.spec, plus every spec mentioning `Submits` or `HiscoreStore` (`grep -rlE "Submits|HiscoreStore" tests`): `112 passed, 0 failed, 11 spec files`. With these mutants the captured outcome "the hiscore shows how many lives were spent" never ships.
Lesson: zz-test/pin-call-site-arguments
Critique: AC3's label promises that the lives "reach its submission, the stored row". Only the pure half is checked.
Consequences: none beyond the case. The adapters already load on stubs in c0129 and f0024; extend one of those fixtures in a new f0145 case rather than editing the promoted specs.
Recommendation: add an adapter case: `Submits` (with `HiscoreStore`'s real source, or a recording stub of it) hears a GameOver with `lives = 6`, and the stored companion row, or the recorded `submit` call, carries 6. Add rows for both mutants.

### F8 [medium] Live mode with a missing product id holds the offer forever and leaves the lobby with no way to buy
Where: §5 `Purchases.ask` (silently does nothing when the id is not a number); Continues holds before asking; G8
Evidence: on the stub, live mode with `ContinueProductId` unset: ask, then 5000 steps → `prompts 0 test screens 0 still offering after 5000 steps true`. In the lobby the same misconfiguration refuses START with nothing opened, so a player with no free game is locked out.
Critique: the ids come from attributes that a publisher sets by hand or by script, and a typo or a missing id is the likely first live failure.
Consequences: a rule for what "configured live" means: either `Pay.mode` takes the ids (live only when both are whole numbers) or `ask` reports that it could not prompt.
Recommendation: make `Pay.mode(raw, products)` answer "live" only when `raw == "live"` and both ids are whole positive numbers. Otherwise the server runs in test mode, so it never charges and never hangs. Say so in G1's wording. Add Pay cases for a missing or bad id, and an adapter case where the offer is not held when nothing could be prompted. If the user would rather fail closed (refuse to run), put that to them.

### F9 [medium] Nothing sets `PaidPlay` or the product ids, so live mode and OC2 cannot be reached
Where: §5 ("attributes the publisher sets"); OC2; Touched modules (no `scripts/` path); `scripts/lib/beta.luau:67,76` (the deploy sets only `LobbyPlaceId`/`GamePlaceId`); game-design.md ("production stays undecided")
Evidence: `grep -n "Attribute" scripts/lib/beta.luau *.project.json` shows only the place-id attributes. Rojo publishes overwrite the place file, so attributes set by hand in Studio are lost on the next publish. There is no production experience.
Critique: an executor can't run OC2, and the charge path (`PromptProductPurchase` → `ProcessReceipt` → grant) is never run against Roblox before players pay.
Consequences: someone has to decide which publish sets the live attributes, and from which repo variables.
Recommendation: state the mechanism. Either the deploy's `attributes` tables gain `PaidPlay`/`PlayProductId`/`ContinueProductId` from repo variables (unset for Beta, so Beta stays test), with a case in the deploy's spec, or a captured follow-up issue (the user's production publish) owns it and OC2 names it. Also add a Beta runtime check (`tests/runtime`) that the purchase path is wired: the remotes exist and `ProcessReceipt` is set.

### F10 [low] Session.continue's `Ready "continue"` event is returned to the adapter and discarded
Where: §2 ("`Ready` with reason `"continue"`"); prototype `Continues.useOne` ignores `Session.continue`'s events
Evidence: by reading. `useOne` calls `Session.continue(s, id)` and drops its result, so the event never reaches `Session.step`'s events (Submits, any client effect).
Recommendation: either queue it into the next step's events, as decline does, or drop the claim from the Design.

## Lesson candidates (reviewer: not written)
- pickman-arch: a new phase between the last life and the game over must be checked against every rule that assumes the run ends within the dying pause, `Hiscores.LEAVE_STEPS` above all. Check: what happens to the run's submission when the player leaves (or the server closes) in the new phase, held or not?
- zz-test: a store stub that runs the transform once, from one thread, can't tell an atomic `UpdateAsync` from a blind read-then-write. Check: does the stub change the stored value between the read and the transform, or call the transform twice?
- pickman-arch: a purchase flow must not order the purchase screen's close before the receipt. Check: what does the design do when `PromptProductPurchaseFinished(bought = true)` comes before `ProcessReceipt`?

Verdict: changes
