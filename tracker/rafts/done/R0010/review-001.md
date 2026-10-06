# Review 001: R0010 (code mode)
Inputs: HEAD 3592d9b on R0010-ghosts, `git diff origin/main...HEAD` with origin/main at c14c6d3 (after `scripts/tracker.sh sync --fetch`); R0010.md and check.sh; f0020, f0021, f0022, f0023, f0032, f0033 documents, check.sh files and acceptance specs; tests/unit/Ghosts, tests/unit/Awareness; src/client/{Main.client,Camera,GhostView,DangerHud}.luau, src/server/Sessions.luau, tests/runtime/structure.luau.

What I checked:
- **Gate**: `scripts/check.sh --full` passes (934 cases, 140 spec files). `tracker.sh check` passes for all six issues: f0020 4/4, f0021 4/4, f0022 3/3, f0023 5/5, f0032 5/5, f0033 4/4. R0010 is 8/10: RC1 and RC2 fail only because of the known `spec()` path problem in the raft's check.sh (already on the PR), so this review does not count them.
- **Sequestration**: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` lists only `R100` renames.
- **R0015 integration points**:
  - `Main.client` feeds GhostView and DangerHud from the same frame, and `Maze.layout` is cached.
  - `Camera.pose` reuses the camera's single `View.interpolate`. Its yaw convention matches Awareness: `-sin`/`-cos` forward, left positive, and the arrow rotation `-deg(bearing)` is right for Roblox's clockwise `Rotation`.
  - `Frame.ghosts = snap.ghosts`.
  - The step order matches f0023's contract. The run's power clock and the ghosts' blue clock tick together, because both decrement only in play and `power` is applied after `Ghosts.step`.
  - `Ready` reasons map to respawn and level, and `playAgain` uses "run" with jump tick `s.tick + 1`, the same as the player's teleport.
  - Ghosts on in `GAME_CONFIG` reach the game-over flow that R0015's Flow and Hud views already handle. The server passes `player.UserId` as the seed and `Maze.DEFAULT` is `classic`. `tests/runtime/structure.luau` only checks instances and remotes.
- **Mutants**: I ran 36 mutants in a scratch clone with its own bare origin. 30 are killed. Two are equivalent:
  - "again" mapped to "level" (`Ghosts.reset` treats both the same).
  - The radar's tunnel-row wrap for walls (the classic tunnel row has no walls past its edges).
  - A third run was not a valid test (`power` was applied twice), and one mutant did not apply.

  Three plausible mutants survive the whole ghost suite; they are F1 and F2 below.
- **Performance**: per tick there is a handful of small tables and four closures per player; per frame, two BFS searches per ghost were measured at about 0.2 ms in prep. Replication is four small ghost records per frame. Nothing O(n²) per tick.

### F1 [medium] Indicator size and brightness can be computed from straight-line distance instead of distance along the maze, and every spec still passes
Where: src/shared/Logic/Awareness/init.luau:185 (`closeness = 1 - clamp(d / maxDistance, 0, 1)`); tests/unit/Awareness/awareness.spec.luau
Evidence: The mutant `closeness = 1 - clamp(sqrt(dx*dx + dy*dy) / maxDistance, 0, 1)` passes every R0010 acceptance spec and the unit specs (169 passed, 0 failed). It keeps the path search for reach and sort order and only changes the size and brightness. A concrete case on the classic maze: player at (12,1) with yaw pi, ghost at (15,1) behind the top-middle wall. The path distance is 11 tiles and the code correctly gives size 0.3125 and brightness 0.358. The mutant gives size 0.8125 and brightness 0.825, a near-maximum warning for a ghost 11 tiles away. The `grows and brightens` case walks a ghost along an open corridor, where the two distances agree, so it cannot tell them apart. The f0033 Design states this rule outright ("The distance is along the maze ... because a ghost behind a wall is not close"), and the user asked for the sense of distance (Theme, Danger aid).
Critique: The code is right today, but nothing pins the property the user asked for. A later refactor that reuses the offset vector, for example while tuning the arrows, would make walled-off ghosts look urgent and no gate would notice. The fix the author will be tempted to make, editing the sequestered awareness spec, is not allowed.
Consequences: A unit spec only needs a pair of tiles where the path distance and the straight-line distance differ. It must use a pose whose bearing is outside the field of view, or the ghost gets no indicator to measure. No new rule or state.
Recommendation: Add a case to `tests/unit/Awareness/awareness.spec.luau`: player at (12,1), yaw pi, ghost at (15,1) normal. Expect one indicator with `distance == 11` and `size` near `minSize + (maxSize - minSize) * (1 - 11/12)` (0.3125), and `brightness` near 0.358. As a contrast, put a ghost 3 tiles away along an open corridor and expect a strictly larger size. Optionally assert `Awareness.pathDistance(classic, {12,1}, {15,1}, 40) == 11` alongside.

### F2 [low] Two smaller design rules have no spec: a ghost leaves the house heading west, and Session seeds the ghosts with its own seed
Where: src/shared/Logic/Ghosts/init.luau:517 (`return "W"` on leaving); src/shared/Logic/Session/init.luau:165 (`Ghosts.new(s.maze, s.seed)`)
Evidence:
- **Leaving west**: replacing `return "W"` with `return "E"` (the ghost turns east once above the door) passes the whole suite. The f0022 Design says the ghost "heads west and `GhostLeft` is emitted". The eyes and release specs only check that the ghost is active on the tile above the door, not where it goes next.
- **Session seed**: replacing `Ghosts.new(s.maze, s.seed)` with `Ghosts.new(s.maze, 1)` passes the whole suite. The idle-player scenario cannot tell, because the seed only matters once a power pellet makes the ghosts wander (f0023 E1). With a constant seed, every player's blue ghosts would wander identically. The f0021 Design says "Session passes its seed".
Critique: Both are cheap to pin, and both are rules a refactor could quietly change: a symmetric "pick the nearer side" exit, or building the set before the seed is known. The impact is small, hence low.
Consequences: The seed spec has to drive a session through a power pellet. The simplest form drives two sessions identically, so it does not depend on any arcade route. None otherwise.
Recommendation:
- In `tests/unit/Ghosts/ghosts.spec.luau`, release Pinky (`start = "house"`, step until `GhostLeft`), take one more step, and expect her heading `W` and her x below `exitX`.
- In `tests/unit/Session/session.spec.luau`, create two `GAME_CONFIG` sessions on classic with seeds 1 and 2. Set both members' ghosts frightened with `Ghosts.power(member.ghosts, 300)` through the documented `member.ghosts` field, step both the same number of in-play ticks, and expect at least one ghost tile to differ. Also check that two sessions with the same seed match.

### F3 [low] `Levels.schedule` is not cached, against the f0021 Design, and the deviation is not recorded
Where: src/shared/Logic/Ghosts/init.luau:395; src/shared/Logic/Levels/init.luau `Levels.schedule`
Evidence: The f0021 Design (Files and API, Scalability) says to "cache the result per (level, tickRate) in the implementation". `tickMode` calls `Levels.schedule(input.level, input.tickRate)` on every tick that is not frightened, for every player. Each call builds a fresh table of 7 numbers, and the f0021 verification log does not mention the deviation.
Critique: The cost is negligible at the server's rate, but this is a silent departure from the Design that its Scalability section relies on.
Consequences: A cached table is shared, so it must be frozen (as the `Levels` rows already are), or one caller's mutation leaks into every set. The cache key must include `tickRate`, which specs vary.
Recommendation: Memoise per `level .. ":" .. tickRate` and return a frozen table. Add a unit case to `tests/unit/Levels` that two calls return equal values and that the result is frozen. Alternatively, record the deviation with its reason in f0021's verification log.

## Judged criteria (code mode only)
None in this raft.

Verdict: changes
