# Review 001: R0004 (design mode)
Inputs: main at 360511a plus the uncommitted prep in the working tree: R0004 doc and check.sh; f0011, f0012, f0013 and f0014 docs, check.sh files and acceptance specs; tracker/architecture.md and tracker/game-design.md diffs; c0041/R0005 for context only. I checked the classic layout independently (a Python count: 240/4/18/2 counts, 34 junctions, 30 corners, 0 dead ends; the doc text matches the spec rows) and recomputed the tick numbers in every Movement and Session spec by hand. In a throwaway scratch worktree (since removed) I built a Maze prototype and a Movement prototype that follow the designs exactly. Every f0011 case (28) and f0012 case (54) passes, so the specs agree with the documented rules. Then I planted mutations and ran probes against them; the results follow.

### F1 [high] AC3 can be passed by an implementation that ignores a turn pressed while the player is on a junction centre
Where: f0012 Design, `step` step 3 ("At a centre (progress == 0), decide"); acceptance/buffer.spec.luau; acceptance/stopped.spec.luau
Evidence: At speed 30 the player ends every 4th step exactly on a centre and still moving. Step 3 is the only place a turn arriving in that step can be taken there. No spec covers that case: buffer.spec only presses before the junction (so the turn is taken on arrival in step 4), and stopped.spec covers a stopped player. The natural "decide on arrival, plus when stopped" implementation (`if s.progress == 0 and not s.moving then decide(m, s) end`) passed all 54 f0012 cases (8 specs) in the prototype. Its behaviour is wrong. In BRANCHES heading E, the player is at (3,2) at time 8, and `Left` arrives at tick 8. The design gives (3, 1.75) heading N at time 9. The mutation gives (3.25, 2) heading E: it misses the junction and keeps a live buffered Left for 23 more steps, which can fire at a later junction the player never chose. This violates AC3's "taken at the first tile centre where that exit exists". Pressing right at the junction is common, because the client renders one tick behind.
Fix: Add a case to buffer.spec with `sim.intent(8, "Left")` on BRANCHES and `sim.expect(9, { x = 3, y = 1.75, heading = "N", moving = true })`. Optionally add the Right/south case at (5,2) with the intent at tick 16.

### F2 [medium] `Back` on the tick right after a buffered turn reverses the new heading: at a corner the player stops facing the wall
Where: f0012 Design, `step` steps 2–4 (a turn is decided on arrival, and `Back` at `progress == 0` sets `moving = Ahead(opposite(heading))`); game-design "`Back` reverses immediately"
Evidence: Prototype of the documented algorithm, CORNER maze, heading E, `Right` at tick 10. At time 16 the player is at (5,1) heading S. `Back` at tick 16 gives (5,1) heading **N**, `moving = false`, and a `Stopped` event: the player stands still facing the wall. On the classic maze, with `Right` buffered and `Back` on the arrival tick at the T-junction (6,23), the player goes **S** (6, 23.25), not back E. The client shows position one tick behind, and the camera is still easing the turn, so the player still sees themselves travelling E or W and presses "reverse", then ends up stuck facing a wall or sent down a third corridor. The docs never say this is intended, and no spec pins it either way. An executor could "fix" it differently without breaking any check.
Fix: Decide the rule and pin it with a case in back.spec. Two options:
- (a) Document it as intended in f0012's decisions, and have back.spec assert the stop facing N at the corner.
- (b) Track the heading the player arrived with. `Back` at a centre reached in the previous step reverses that heading (on the corner, back to W). Then assert W and moving.

Option (b) changes the meaning of "reverses" slightly, so confirm it with the user if game-design needs a note.

### F3 [medium] `TUNNEL_MARGIN = 10` is one tile short for the classic maze: looking down the tunnel shows the end of the world
Where: f0014 Design, "Tunnels" and `View.walls`; acceptance/walls.spec.luau (`TUNNEL_MARGIN` toBe 10, coverage at margin 10); OC1 step 7
Evidence: Row 14 is `"      .   #HHHHHH#   .      "`. Its first wall east of the west edge is x=10, and its first wall west of the east edge is x=17. With a 10-tile margin the rendered x range is −10..37. Heading W from the tunnel mouth, the sightline runs through the copies of x=27..18 (all open) to x=−11 (≡17, a wall), which isn't rendered. Heading E, x=38 (≡10) isn't rendered either. The floor stops at the margin as well. So down the tunnel the player sees the floor edge and the sky about 11 tiles away, not the far side's wall. That fails OC1 step 7 ("shows the far side ahead"), and the value is pinned in a sequestered spec, so the executor can't correct it.
Fix: Use a margin of at least 11. I'd suggest 12: my Python count gives 240 rects over 1,032 wall tiles, still more than 4× merging (960 < 1032). Update `View.TUNNEL_MARGIN`, the f0014 text and the walls.spec expectation. Or derive the margin from the maze (the distance from each wrapping edge to the first wall along the tunnel rows, plus one).

### F4 [low] RC1 passes with a stub scenario spec
Where: R0004 check.sh RC1
Evidence: RC1 only requires that some `tests/scenario/*.spec.luau` contains the strings `@logic/Session` and `@tests/lib/sim` (a comment is enough) and passes. `t.spec("x", function() end)` with those two requires satisfies it. The behaviour is already proven by f0013 AC3 (tick.spec drives Session through the harness), which is why this is low. What RC1 was meant to add, the readable story (stop at (6,23) at tick 28, then turn north, and so on), is unchecked.
Fix: Write the story in prep as a sequestered spec, for example `f0013/acceptance/story.spec.luau`, with its expectations, and have RC1 run it. Or drop RC1 as redundant with f0013 AC3.

### F5 [low] Roblox's runtime support for `@game` is only doc-checked, and the only real test (OC1) doesn't block the merge
Where: R0004 Risks ("Roblox rejects `@game` at runtime"); c0041 E2
Evidence: The whole of a2's "Proves" line (walking the maze in Studio) depends on `require("@game/…")` working in the engine. That's backed by a DevForum/changelog reading only. Per the tracker skill, Observed criteria don't block the merge, so the raft can merge with both adapters failing at boot, and the fallback is a later chore that touches the place rules.
Fix: Before `tracker.sh start R0004`, have the human run a 2-minute Studio probe: one Script doing `require("@game/ReplicatedStorage/Shared/…")` of any ModuleScript. Record the pass/fail in c0041 E2, and add it to R0004's Order step 0.

### F6 [low] The Studio playtest setup and the floor and door geometry are unspecified
Where: f0014 `MazeView.luau` ("one floor Part covering the maze", "one thin Part per door tile"); OC1; SETUP.md (`rojo serve` into whatever place is open)
Evidence: `default.project.json` has no `Workspace`, so a place made from the default Baseplate template keeps its Baseplate and SpawnLocation. The Baseplate's top face is Y=0, the same plane the walls stand on, so a black floor at Y=0 will z-fight with it. The 12×12 SpawnLocation at the origin reaches into corridor tile (1,1), since walls are only ±4 studs around tile (0,0). The floor's Y and thickness and the door's thickness are left to the executor.
Fix: Specify the floor as top face at Y=0, extending downward (for example 1 stud thick). Specify the door size (for example tile × wallHeight × 1, centred on the tile). Start OC1 with "open an empty place (or delete Baseplate and SpawnLocation) and `rojo serve`".

### F7 [low] The View API sketch contains a banned engine word that is easy to copy into Logic
Where: f0014 Design, the `View.action` signature comment `-- by Enum.KeyCode name, e.g. "W", "Up", "Space"`
Evidence: `tests/meta/architecture.spec.luau` scans raw Logic source, comments included, for `Enum`, and f0012's executor note says so. Copying the documented signature block into `View/init.luau` as written fails the meta rule.
Fix: Reword it as "by key name, e.g. "W", "Up", "Space"", and add the "no engine words in comments" note to f0014's executor notes.

### F8 [low] AC5's wording contradicts its own spec: the player does move in the step `Back` arrives
Where: f0012 AC5 ("reverses in the step it arrives, without moving the player that step"); acceptance/back.spec.luau
Evidence: back.spec expects x = 2.25 at time 5, then `Back` at tick 5, then x = 2 heading W at time 6. At a centre it expects x = 2 to go to 1.75. The design (step 2, then step 4 advancing) moves the player `speed` units in the new direction in that same step. Read literally, AC5 asks for a different implementation than the spec checks.
Fix: Reword AC5 as "reverses in the step it arrives, from the current position (no jump), and moves `speed` units the new way in that step".

### F9 [low] `wrapTick` covers only tunnel jumps; later teleports will make the camera slide
Where: f0013 snapshot v1 (`wrapTick`: "tick of the latest Wrapped event"); f0014 `View.interpolate`
Evidence: The client lerps unless `wrapTick > prev.tick`. Rafts c and d will respawn the player at the spawn after a death or a level clear with no Wrapped event, so for one tick the camera will lerp through walls across the maze. The name and definition tie the flag to tunnels only.
Fix: Define it now as "the tick of the latest position discontinuity (tunnel wrap, and in later rafts respawn or level reset)". Either rename it (`jumpTick`) while the specs are still editable, or add a line under f0013 Maintainability that every later teleport must set it.

Verdict: changes
