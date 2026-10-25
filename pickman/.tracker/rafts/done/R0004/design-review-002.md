# Review 002: R0004 (design mode)
Inputs: main at 360511a plus the uncommitted prep in the working tree: R0004 doc and check.sh; the f0011, f0012, f0013 and f0014 docs, check.sh files and 25 acceptance specs; the tracker/architecture.md and tracker/game-design.md diffs; design-review-001 and design-refute-001; c0041/R0005 only where R0004 depends on it. In a scratch worktree (/tmp/r0040-review2, removed afterwards) I copied in the prep's prototype `src/` together with the c0041 prototype resolver changes and the current tracker files. There, all four member check.sh files pass (146 cases), and `tracker.sh promote-check R0004` shows type errors only in the prototype `src`, none in the specs. I recomputed by hand the expected ticks in every f0012 and f0013 spec that uses the sim harness, and they agree with the documented `step` rules. Then I planted mutations and wrote probes; the results follow.
Dropped from review-001: F1, F2, F3, F4, F5, F6, F7, F8, F9 (each fix checked against the files. The leftover stale references from F4 and F9 are collected in F6 below)

### F1 [high] AC5 passes an implementation where `Back` at a tile centre keeps the buffered turn, which then fires behind the player
Where: f0012 Design, `step` step 2 (`Back`: "In both cases, clear the buffer", line 84); AC5; acceptance/back.spec.luau "clears a buffered turn"
Evidence: back.spec's only buffer case presses `Back` mid-tile (tick 1, progress 30), and every other `Back` case has nothing buffered. Mutant: clear the buffer only in the `progress > 0` branch (`if s.progress > 0 then clearBuffer(s) end`). It passes all 8 f0012 checks and all 7 f0013 checks. Its behaviour is wrong. On BRANCHES heading E, with `Right` at tick 9 (meant for the south exit at (5,2)) and `Back` at tick 12 on the (4,2) centre, the design gives heading W and x = 2.75 at time 17. The mutant turns the stale Right relative to the new heading (N), taking the north branch at (3,2): heading N at time 17. That's exactly what the design's "A stale turn from before a reversal never fires behind the player" forbids. Reversing at a centre is common: the client renders a tick behind, so "I'm at the junction, go back" lands on a centre.
Fix: Add a back.spec case: `sim.intent(9, "Right")`, `sim.expect(12, { x = 4, y = 2, heading = "E" })`, `sim.intent(12, "Back")`, `sim.expect(17, { x = 2.75, y = 2, heading = "W" })`. It passes on the prep prototype and fails the mutant; I ran both.

### F2 [high] AC3 passes an implementation where a new press replaces the direction but not the window, so a re-pressed turn expires early
Where: f0012 Design, step 2 (`Left`/`Right`: "`buffered = intent` and `bufferLeft = c.turnBufferTicks`. It replaces any earlier one", line 85); AC3 ("a press stays pending for exactly `turnBufferTicks` steps"); acceptance/buffer.spec.luau
Evidence: The window-boundary case tests a single press, and "keeps only the latest" uses a 24-tick window, where the old count still has plenty of time left. Mutant: reset `bufferLeft` only when nothing is buffered (`if s.buffered == nil then s.bufferLeft = c.turnBufferTicks end; s.buffered = i`). It passes all f0012 and f0013 checks. Its behaviour is wrong. On BRANCHES heading E with `turnBufferTicks = 6`, `Right` at tick 9 is re-pressed at tick 10. Per the design, the tick-10 press is pending in steps 10..15 and is taken at (5,2) in step 15, which gives (5, 2.25) heading S at time 17. The mutant keeps the tick-9 window (steps 9..14), and the player goes straight on (heading E). A player who taps the direction again to be sure gets a shorter window than one who pressed once. That's the opposite of what the buffer promises, and nothing pins it.
Fix: Add to buffer.spec's window case: with `{ speed = 30, turnBufferTicks = 6 }`, `sim.intent(9, "Right")`, `sim.intent(10, "Right")`, `sim.expect(17, { x = 5, y = 2.25, heading = "S" })`. It passes on the prototype and fails the mutant. Optionally add the same with `Left` at 9 and `Right` at 10, so the direction changes as well.

### F3 [medium] A turn pressed just after a junction centre usually diverts the player at a later junction: the "rarely fires at the one after" claim is false
Where: f0012 Decisions, "Turn buffer" (line 30: "short enough that a stale press rarely fires at the one after"); R0004 Risks ("latency makes turns feel late"); game-design pillar 3 ("Fair and readable … The player can always tell where they're going")
Evidence: I measured this with the prep's Movement prototype on the classic maze. For each of the 220 (junction centre, heading, turn) cases where the player passes a centre whose turn exit exists, I delivered the press one step late (at +0.25).
- In 156 cases (71%) the stale turn still fired later.
- In 78 cases (35%) it fired at a later junction where going straight was open. So it turned the player into a corridor they hadn't chosen, a mean of 15.5 ticks (0.5 s, about 4 tiles) after the press.

A press this late is the normal case, not a rare one. The camera shows position(t) only at alpha = 1, one tick after snapshot t arrives, which is about when the server runs step t (f0014 "Interpolation"). So a key pressed the moment the view reaches the centre arrives after the decision even at zero latency, and Beta latency adds more ticks. The design's only mitigation is press-ahead ("absorbs up to about 0.8 s of press-ahead"). Nothing handles late presses, and no spec or proxy measures it. It also can't be tuned later without a sequestered-spec or game-design change.
Fix: This is a product decision, so take it to the user and record it in game-design.md. The options:
- (a) Discard a Left/Right that arrives within N ticks after passing a centre where that exit existed ("missed it").
- (b) A post-centre grace window: take the turn if it arrives within `speed` units past such a centre. It snaps back, so it needs a jump rule.
- (c) Keep the rule, but correct the f0012 text and add a measurable proxy.

Whichever is chosen, pin it as a measurable proxy in f0012. For example, "a press 1 tick after a junction with that exit never diverts at a later junction where straight is open", or a bound on the 35% rate above, measured by a spec over the classic maze.

### F4 [medium] The server starts simulating at `PlayerAdded`, before the client can see anything, and nothing waits for the client to be ready
Where: f0013 server adapter sketch (line 103: join on `PlayerAdded`, then every Heartbeat steps and `FireClient`s); f0014 `Main.client.luau` (connects `Snapshot.OnClientEvent` only after its own script loads); f0014 OC1 steps 1–2 (line 224: "starts … at the spawn … and moving", "stops at the T-junction after about 1 s")
Evidence: The session begins stepping on the first Heartbeat after `PlayerAdded`, and the player walks from (13,23) to the stop at (6,23) in 28 ticks (0.93 s, f0013 tick.spec). The client has to receive the place, copy StarterPlayerScripts, run `Main`, `WaitForChild` the remotes and connect the listener before it sees a snapshot. Until then the snapshots queue up on the remote. For the 2-player "Clients and Servers" test in f0013 OC1, the client processes start separately. When a client finally connects, it gets a burst of queued snapshots, and `Camera` shows the latest. So the human typically first sees the player already standing at (6,23), and OC1 steps 1–2 can't be observed as written. This isn't listed as an unknown. It also becomes a correctness problem in the very next rafts. With ghosts (raft d) and the mode timers, the world runs against a player who can't see it yet, and a slow-loading client can lose a life before its first frame. Adding a start gate then means an unplanned change to the snapshot and remote protocol.
Fix: Add a client-ready handshake now; it's small and keeps the adapters thin. Declare a third RemoteEvent `Remotes.Ready` in `default.project.json` and pin it in f0013 place.spec (AC7). `Main.client` fires it after connecting `OnClientEvent`. `Sessions` creates and joins the session on `Ready` (a nil or first-time guard, which JC1 already allows), not on `PlayerAdded`. Alternatively, keep the current flow, record it as a decision, and reword OC1 steps 1–2 ("the view may start at the first stop; press S to see the movement") so the Observed criteria match what the design delivers.

### F5 [medium] The floor must span the tunnel margin "on the wrapping axes", but only `View.walls` knows which axes wrap, so the adapter has to decide it (failing JC1) or hard-code it
Where: f0014 `MazeView.luau` (line 100: "One floor Part covering the maze plus the tunnel margin on the wrapping axes"); "Tunnels" (line 52: "The floor spans the same margin"); JC1 Fail ("choosing which tiles become parts", "maths beyond converting `View` numbers")
Evidence: The wrap test ("any tile on column 0 / row 0 is ghost-passable") is specified only inside `View.walls`, and View exposes no bounds or floor API. An executor following the design has three options:
- re-implement the wrap test in `MazeView`, a branch over maze tiles that JC1's rubric fails, and a failed Judged criterion blocks the merge (tracker skill, Merging 1);
- derive the extent from the min/max of the returned rects, an undocumented inference;
- do what the prep prototype does: `(m.width + 2 * View.TUNNEL_MARGIN)` on x always and no margin on y. That's wrong for a y-wrapping maze (no floor under the vertical tunnel copies), and it adds floor beside a maze without tunnels.

The design leaves this to the executor, and each choice fails either JC1 or the design.
Fix: Add a pure `View.bounds(m: Maze.Maze, margin: number?): Rect`, the rendered tile range with the margin applied only on wrapping axes. Have `View.walls` use it, and have the floor size come from it (`MazeView` only converts it to studs). Pin it in walls.spec: classic gives `{ x0 = -12, y0 = 0, x1 = 39, y1 = 30 }`, the vertical SHAFT maze with margin 2 gives y −2..4 and x 0..2, and a maze without tunnels gives the plain grid.

### F6 [low] Stale references after the round-1 renumbering and rename
Where and evidence:
- R0004 line 73: "The scenario story (RC1)". RC1 is now adapter size, and the story is unchecked.
- R0004 line 114: "The place specs, the meta rule and RC3 fail". There is no RC3.
- f0013 line 131: "R0004's scenario story (RC1)".
- f0014 line 132: "RC2 caps adapter size" (it's RC1).
- f0014 line 169: "R0004 RC2 and RC3" (they're RC1 and RC2).
- f0013/check.sh line 13: the label "AC4: snapshot schema v1 and wrapTick". The field is `jumpTick`, and check.sh is sequestered, so it can't be fixed during execution.
- f0011 line 165: "the raft total is 144 cases". R0004 says 146, and a run gives 146.

An executor cross-checking RC numbers against check.sh will stop and ask.
Fix: Update each reference. Rename the AC4 label to "snapshot schema v1 and jumpTick".

### F7 [low] `Camera.push` drops every snapshot whose tick is not above the last one it saw, so a fresh Session for the same client freezes the camera
Where: f0014 `Camera.luau` ("ignores `tick <= latest.tick`"); f0013 Maintainability ("Teleports … set `jumpTick`")
Evidence: `Session.new` starts at tick 0. Raft c's "play again" (f0031) or level reset is the natural place for the adapter to replace a player's Session. After that, every new snapshot has `tick <= latest.tick` until the new session catches up with the old one's tick count, so the camera stays frozen for as long as the previous game lasted. f0013 only asks later teleports to set `jumpTick`. It doesn't say that a session's tick must stay monotonic for a connected client.
Fix: Add a line to f0013 Maintainability: "a connected client's session is never replaced: resets happen inside `Session` (tick keeps counting, `jumpTick` is set)". Or make `Camera.push` reset its history when `snap.tick < latest.tick`, and put that rule in `View` so it's specced.

Verdict: changes
