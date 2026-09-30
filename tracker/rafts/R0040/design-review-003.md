# Review 003: R0040 (design mode)
Inputs: main at 36d7015 plus the uncommitted prep in the working tree: R0040 doc and check.sh; the f0100, f0110, f0120 and f0130 docs, check.sh files and 26 acceptance specs; the tracker/game-design.md and tracker/architecture.md diffs; design-review-001/002 and design-refute-001/002; c0390/R0050 only where R0040 depends on it. In a scratch worktree (/tmp/r0040-review3, removed afterwards) I combined the prep's prototype `src/` and c0390 resolver changes with the current tracker files. There, all four member check.sh files pass (26 specs, 155 cases, which matches the docs). I recomputed every grace.spec and the new back.spec and buffer.spec expectations by hand against the documented `step` order, and they agree. I also checked the invariants.spec distance rule (`2·off + speed`) against the grace geometry and found it exact. Then I planted mutants and ran probes; the results follow.
Dropped from review-002: F1, F2, F3, F4, F5, F6, F7 (each fix is in the files. F3 was resolved by the user's cornering-grace decision, and F1 below covers what is left of it.)

### F1 [high] AC9 doesn't pin what happens to a press two or more ticks after a centre: an implementation that discards it passes, and grace.spec's case title says it "never fires further on", which contradicts the design
Where: f0110 Design, step 2 (a Left/Right that fails the grace test goes into the buffer); AC9 ("Two steps late is too late at any speed"); acceptance/grace.spec.luau "two ticks late is too late, and the missed turn never fires further on"; game-design.md, Movement ("so a slightly late press never fires at a later junction"); R0040 Theme ("it never fires later")
Evidence:
- **The design and spec wording disagree.** Under the design, a press two ticks after the centre is buffered, and it fires at the next junction that has that exit. The grace.spec case uses BRANCHES, which has no later north exit, so its "never fires further on" is vacuously true. An executor who takes the title (and the game design's "never fires at a later junction") literally would discard the press instead.
- **A wrong implementation passes.** Mutant: in the non-grace branch, drop the press (don't buffer it) when `progress > 0 and progress*2 < U and Ahead(h)`. It passes all nine f0110 specs and the f0120 Session specs (91/91).
- **A spec case that tells the two apart:** maze `{ "#########", "###.#.###", "#P......#", "#########" }`, heading E, speed 30, `Left` at tick 10 (two ticks after the (3,2) centre). On the prototype (the design), the player is at (5,2) heading N at time 16 and at (5, 1.75) N at time 17. The mutant is still heading E.
- **The product claim holds only for exactly one tick.** I repeated review-002 F3's measurement over all 220 (junction, heading, turn) cases on the classic maze. A press one tick after the centre now diverts at a later junction 0 times out of 220. A press 2, 3 or 4 ticks after still diverts 78/220 times (35%), the same rate as before grace. One tick is only the zero-latency display lag. Pressing a few tens of milliseconds after the view reaches the centre, or any network latency (Beta), gives two or more ticks. So "a slightly late press never fires at a later junction" is true only in a window about 33 ms wide.
Fix:
- Choose one rule and pin it. Either keep the design (buffer it) or have the user choose discarding. This is the last round, so the prep author must pick.
- If the design stays: add the case above to grace.spec (`sim.intent(10, "Left")`, `sim.expect(16, { x = 5, y = 2, heading = "N" })`), and retitle the existing case "two ticks late is not a grace turn".
- Reword game-design.md, R0040 Theme and AC9 to "a turn arriving exactly one tick after … is taken there; a later press is buffered as usual".
- Add one sentence to R0040 Risks (latency) noting that grace doesn't help once there's network latency.

### F2 [medium] Grace also applies right after a turn or `Back` taken at that centre, so a double-tapped Right that straddles the centre sends the player back the way it came, with a diagonal jump. Nothing specifies or pins this
Where: f0110 step 4 (`left = true` whenever the advance starts from `progress == 0`, whatever happened at that centre); the grace branch in step 2; f0110 Decisions ("covers the one-tick display lag … like the arcade's cornering"); the re-press rule from review-002 F2 ("a player who taps the direction again to be sure")
Evidence:
- **The scenario.** On BRANCHES heading E, `Right` at 13 is taken at (5,2) (heading S from time 16). A second `Right` at 17, one tick after leaving that centre, passes the grace test: turn(S, Right) = W, and W is open because the player came from there. The player cuts back west and is at (4,2) heading W at time 20 (prototype). With the second press at 16 (on the centre), the at-centre rule gives the same result. With it at 15 it just replaces the buffer, and the player goes south.
- **The effect.** Before grace, a double tap that straddled the centre reversed the player in a 1-tick window. Grace widens that to 2 ticks. It also turns the reversal into a diagonal jump from (5, 2.25) to (4.75, 2), which is not the "missed turn" case grace was chosen for. The same applies to a `Back` at a centre followed by a Left/Right on the next tick.
- **Nothing pins it.** Mutant: set `leftCentre` only when the player left the centre on the heading it arrived with. It passes all f0110 and f0120 specs (91/91). So the executor may implement either behaviour.
Fix: Make it a product decision, briefly, with the user, or take the conservative reading.
- Conservative reading: grace applies only if the player left that centre on its arrival heading, meaning it went straight through. Step 4 would say "`left = true` only if no turn or `Back` was taken at this centre in this or the previous step". Add a grace.spec case: `Right` at 13 and 17 on BRANCHES gives (5, 2.5) heading S at time 18.
- Otherwise, record the U-turn behaviour in f0110's Decisions and pin it with the same inputs expecting (4.5, 2) W at time 18.

### F3 [medium] The Ready start gate, a user decision, has no check: an adapter that starts sessions on `PlayerAdded` and never fires `Ready` passes every criterion
Where: f0120 Decisions ("Ready handshake") and the adapter sketch; f0130 `Main.client.luau` ("then fires `Remotes.Ready:FireServer()` once"); f0120 AC7 / place.spec (it only checks that the `Ready` RemoteEvent exists); f0130 AC6; R0040 RC1 and RC2; f0130 OC1 step 1
Evidence:
- **The mutant.** I changed the prototype `Sessions.luau` to connect `Players.PlayerAdded` instead of `Ready.OnServerEvent`, and deleted the client's `FireServer()` line. f0120 place.spec and f0130 place.spec still pass (6/6), and so do RC1 and RC2.
- **Why it slips through.** The only place the gate can be seen is f0130 OC1 step 1. That's Observed, so it doesn't block the merge, and on a fast local Studio load it may look the same anyway. That's the scenario review-002 F4 was raised for.
- **What depends on it.** The user's reason for the gate (ghosts and timers must not run against a client that can't see yet) only shows up in raft d, after this PR has merged.
Fix: Add a cheap proxy to the (still unsequestered) place specs. Both scripts' `Source` is available through `@tests/lib/place`.
- f0120 place.spec: the `Sessions` source contains `Ready` and `OnServerEvent`, and contains no `PlayerAdded`.
- f0130 place.spec: the client `Main` source contains `Ready` and `:FireServer(`, at a position after the `Snapshot` … `OnClientEvent` connection.
- Name it in AC7 and AC6 ("… and sessions start on Ready").

### F4 [low] Stale or inconsistent text after round 2
Where and evidence:
- R0040 RC0 (line 108) says "f0110 AC1–8". AC9 now exists, and check.sh runs it.
- f0110 line 137 ("the eight acceptance specs") and line 141 ("passes all eight Movement specs"). There are nine.
- f0110's Acceptance criteria list AC9 before AC8, but check.sh runs them AC7, AC8, AC9. The check.sh header says checks are "in the same order as the issue doc".
- f0130's `Rect` type comment says "y0 == y1 (one row)", but `View.bounds` returns a multi-row `Rect` (the classic maze gives y 0..30). An executor typing `bounds` may think it needs a separate type, or assert `y0 == y1`.
- f0120's residual unknown (line 162) still names "`PlayerAdded`/`PlayerRemoving`". The engine behaviour to watch now is `Ready.OnServerEvent`.
- R0040 Theme presents the Back, cornering-grace and start-gate lines as "(quoted)", but none of them matches game-design.md word for word. For example, the Theme has "it never fires later" where game-design has "so a slightly late press never fires at a later junction".
Fix: Update each line. Move AC9 after AC8 in f0110, or renumber grace as AC8 and config as AC9 in both the doc and check.sh. Change the `Rect` comment to "inclusive tile range; `walls` rects have y0 == y1". Copy the quotes verbatim.

Verdict: changes
