# Review 004: R0040 (design mode)
Inputs: main at df9643d plus the uncommitted prep in the working tree: the R0040 doc and check.sh; the f0100, f0110, f0120 and f0130 docs, check.sh files and 26 acceptance specs; the tracker/game-design.md and tracker/architecture.md diffs; design-review-001/002/003 and design-refute-001/002/003. c0390/R0050 was read only where R0040 depends on it. In a scratch worktree (removed afterwards) I combined the prep's prototype `src/` and adapters with the current tracker files. There, all four member check.sh files pass (26 specs, 162 cases). I recomputed every grace.spec expectation by hand against the documented `step` order (TWO at 10, 11 and 13; PAIR at 10; HOOK at 13 and 18), and they agree. I checked each refute-003 answer against the files. Then I planted mutants and a design sweep on the classic maze; the results follow.
Dropped from review-003: F1, F3, F4 (F1: the user's missed-turn rule is now specified, and F1 below is a new gap in it. F3: place.spec now checks the Ready gate. F4: the listed lines are fixed, and the leftovers are in F4 below.)

### F1 [high] The missed-turn rule only works until the next centre, so a press 4 or more ticks late still diverts the player at a later junction. This contradicts game-design.md, the R0040 Theme, AC9 and the latency Risk, and grace.spec can't tell the two rules apart
Where: f0110 Decisions "Missed turns" (line 36) and step 2 **Missed** (line 97): `exitHere` needs `tile` itself to have the exit. game-design.md Movement (line 31): "discarded while the player is still nearer that junction than the next one ahead with that exit, so a late press never diverts the player at a later junction". R0040 Theme (line 30, same quote). f0110 AC9: "discarded while the player is nearer it than the next centre ahead with that exit". R0040 Risks (line 120): "a late press becomes a missed turn (discarded, never a wrong turn)".
Evidence:
- **How the design works.** `tile` moves on at every centre. Once the player passes the next centre (J+1) after the junction it went straight through (J), `exitHere` looks at J+1. J+1 usually lacks the exit, so the press is buffered and taken at the next junction that has it. The player is still nearer J at that point.
- **A concrete case.** Maze `{ "##########", "###.##.###", "#P.......#", "##########" }` has north exits at (3,2) and (6,2). The player heads E at speed 30 and passes (3,2) at time 8. `Left` at 13 arrives 1.25 tiles past (3,2) and 1.75 tiles before (6,2), so the game design says discard. On the prototype, the player turns N at (6,2) at time 20 and is at (6, 1.75) heading N at 21.
- **How often this happens.** I swept every (junction passed straight, heading, turn with that exit) case on the classic maze. For each press delay of d ticks after the centre where the game design says "discard", I compared the run with the press against the run without it. For d = 2 and 3 there are 0 diversions in 104 cases each. For d = 4 and 5 there are **78 of 104**. Over d = 2..16 it's 408 of 856. d = 5 is 167 ms, which is ordinary human lateness or ordinary network latency. So the Risk's claim "never a wrong turn" is false in exactly the latency case it describes.
- **The spec can't tell the rules apart.** Every grace.spec case uses junctions at most 2 tiles apart, and at that spacing "nearer the passed junction" and "before the next centre" agree. I wrote an implementation that follows the game design: a `run` counter of centres passed straight since the last turn, `Back` or stop; walk back up to `run` centres to the nearest one with the exit, and discard if that distance is less than `nextExitDistance`. It passes all nine f0110 specs and also discards the case above. So both the design and the product rule pass `check.sh`.
Fix: Either implement the product rule or get the user to narrow it. Do one of these:
- **Keep the product rule (preferred; it's what the user decided).** In step 2 of f0110, replace `exitHere … progress < nextExitDistance(h)` with `prevExitDistance(h) < nextExitDistance(h)`. `prevExitDistance` walks back from `tile` over the centres passed straight since the last turn, `Back` or stop, and returns `j·U + progress` for the first one with exit `h` (∞ if there is none). Replace `straight` with a counter (`run`, capped at width + height), or add the counter next to it. At `progress == 0` the current centre's exit belongs to the step-3 decision, not to this rule. Add the case above to grace.spec: `sim.intent(13, "Left")` and `sim.expect(21, { x = 6.25, y = 2, heading = "E" })`.
- **Or narrow it.** The user rewords game-design.md, the Theme, AC9 and the Risk to "until the player reaches the next centre", and grace.spec pins the case above expecting heading N at 21.

### F2 [medium] (repeat of review-003 F2, the `Back` half) Nothing pins "`Back` clears `straight`", so an implementation that lets a Right right after a `Back` at a centre spin the player off sideways passes every spec
Where: f0110 step 2 `Back` ("In both cases … set `straight = false`", line 93) and Decisions "Only after going straight … not after a turn or `Back` taken at that centre". AC9 says only "never after a turn at that centre". back.spec and grace.spec have no `Back`-then-turn case.
Evidence:
- **Mutant M4:** clear `straight` on `Back` only mid-tile. **Mutant M3:** never clear it on `Back`. Each passes all f0110 specs and f0120's Session specs (100/100).
- **What M4 does.** On BRANCHES heading E: `Back` at 8 (on the (3,2) centre), then `Right` at 9. The mutant grace-turns N at (3,2) (heading N at time 10). The design keeps heading W, at (2.5, 2). That's the Back-then-turn spin the user excluded.
- **What M3 does.** On maze `{ "#########", "#P......#", "##.##.###", "#########" }` heading E: `Back` at 14 (mid-tile), then `Left` at 15. The mutant treats the press as missed at (5,1), a tile the player never passed, and continues W (heading W at 25). The design buffers it and turns S at (2,1), reaching (2, 1.25) heading S at 25.
Fix:
- Add both cases to back.spec or grace.spec: `sim.intent(8,"Back"), sim.intent(9,"Right"), sim.expect(10,{x=2.5,y=2,heading="W"})` on BRANCHES, and the second maze with `sim.expect(25,{x=2,y=1.25,heading="S"})`.
- Make AC9 say "never after a turn or `Back` at that centre".

### F3 [medium] Nothing pins the rule that a grace turn or a missed press also clears an older buffered turn, so a stale turn can still fire later, against AC3's "the latest press replaces an earlier one"
Where: f0110 step 2 **Grace** ("… and clear the buffer") and **Missed** ("clear the buffer and drop the press"); AC3; AC9.
Evidence:
- **Mutant M1 (a missed press keeps the old buffer)** and **mutant M6 (a grace turn keeps the old buffer)** each pass all f0110 and f0120 Session specs (100/100).
- **M1 case.** On BRANCHES heading E: `Right` at 5 is buffered, because (3,2) has no south exit. `Left` at 10 is a missed press at (3,2). The design keeps heading E, at (5.25, 2) at time 17. M1 fires the stale Right at (5,2) and is heading S at 17.
- **M6 case.** On `{ "#######", "###...#", "###.###", "#P....#", "#######" }` heading E: `Right` at 5, then `Left` at 9 (a grace turn N at (3,3)). The design stops at the (3,1) corner (`moving = false` at time 17). M6 turns E there (heading E at 17).
- **Why it matters.** In both cases the player changed their mind, and the abandoned turn fires anyway.
Fix: Add both cases to grace.spec with the design's expectations (`sim.expect(17, { x = 5.25, y = 2, heading = "E" })`, and `sim.expect(17, { x = 3, y = 1, heading = "N", moving = false })`).

### F4 [low] Leftover stale or unspecified text
Where and evidence:
- **Stale counts.** R0040 E3 says "26 acceptance specs (155 cases after design-review-002)" and "22 plausible wrong implementations". f0100 E3 says "the raft total is 155 cases". The specs now have 162 cases, and f0110 alone lists more than 22 mutants. f0110 Affected specs (line 142) still says "the eight acceptance specs".
- **Ready check not named.** f0120 AC7's text and its check.sh label don't mention that sessions start on Ready, although place.spec now asserts it. Refute-003 F3 said AC7 was updated; only f0130 AC6 was.
- **Spawn state unspecified.** `spawn`'s initial `buffered`, `bufferLeft`, `leftCentre` and `straight` aren't given. Mutant M2 (`straight = true` at spawn) passes every spec. It grants grace or a missed turn at a spawn with a side exit. That's moot on the classic spawn (13,23), but not on test mazes.
- **Stale spec comment.** grace.spec's header comment ("It never fires at a later junction") describes grace only. With F1 fixed it's fine; otherwise it overclaims.
Fix:
- Update the counts.
- Add "and sessions start on `Ready`, not `PlayerAdded`" to f0120 AC7 and its check label.
- Add to the `spawn` line: "`buffered = nil`, `bufferLeft = 0`, `leftCentre = false`, `straight = false`".

Verdict: changes
