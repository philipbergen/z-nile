# Pickman game design

This is the source of truth for product decisions. Every raft design must agree with it. Changes happen through the user, never during execution. Items marked **(prep)** are decided in that raft's ticket-prep.

## Pillars
1. **It's Pac-Man, seen from inside the maze.** The classic rules and feel come first, and the first-person view is the twist.
2. **Deterministic game code.** Everything that decides an outcome runs in pure Logic, can be simulated headless and is tested in CI. Roblox renders and relays input.
3. **Fair and readable** in first person. The player can always tell where they're going and where the danger is.

## Decisions (2026-09-29, by the user)
| Topic | Decision |
|---|---|
| Movement | **Rail movement with free look**, described below |
| Players | **Solo mazes.** Each player gets their own maze instance (with their own ghosts) inside a shared server. Other players' mazes aren't visible. Logic should still allow N players per maze later. |
| Authority | The **server** simulates every maze. Clients send intents and render the replicated state. A session starts only when its client signals it's ready (user, 2026-09-29). |
| Deploy | A separate, private **Pickman Beta** experience. Every PR that becomes ready for review is published there (last one wins). Production publishing will be decided later. |
| Hiscores | A **global all-time top N**, plus **daily** and **weekly** boards. No personal-best feature for now. |
| Platforms | Desktop (keyboard and mouse) and **mobile (touch)**. Gamepad isn't planned; it gets the same intents if it's added later. |

## Movement model: rail with free look
**All durations and speeds in this document are game time** (30 ticks per game second); the game is played at half speed, so real time is twice as long (see *Game speed* below).

- **The maze is a grid of tiles.** Walls are whole tiles. Walkable tiles form corridors, and a junction is a tile with more than 2 exits.
- **Movement:**
  - The player always moves along the current corridor at the level's speed and stops at a wall. Level 1 is **7.5 tiles/s of game time** (3.75 in real time, see Game speed), the arcade's 80% (R0040). Per level (R0090, *Pac-Man Dossier* Table A.1, relative to level 1): levels 2–4 ×1.125, 5–20 ×1.25, 21 and on ×1.125, in whole units per tick (30, 34, 38, 34).
  - **Corners are classic** (decided by the user, 2026-09-29): at a corner the player stops unless a turn into it is buffered. There is no automatic cornering.
  - There is no free strafing; position is always on a corridor centreline.
- **Turn intents:** `Left`, `Right`, `Back` and `Forward`, relative to the current heading.
  - A turn intent is **buffered** and taken at the next tile where that exit exists.
  - `Back` reverses immediately: a literal reverse of the current heading, as in the arcade, even right after a turn (user, 2026-09-29).
  - The buffer expires after **0.8 s of game time** (24 ticks; R0040), 1.6 s in real time. A re-press restarts it.
  - **Cornering grace** (user, 2026-09-29): a turn arriving one tick after passing straight through a centre where that exit exists is taken there, cutting the corner.
  - **Missed turns** (user, 2026-09-29): a later press for a turn the player just passed straight by is discarded while the player is still nearer that junction than the next one ahead with that exit, so a late press never diverts the player at a later junction. A press nearer the next such junction is buffered for it.
- **Look:** the camera's yaw and pitch are free and never change the heading. A "snap look to heading" action recentres it.
- **Collisions are grid rules in Logic:**
  - wall contact means stopping at the tile edge: the player is one tile wide, so its front edge meets the wall when its centre reaches the last tile's centre (R0040);
  - pellets are eaten when the player enters a tile;
  - player and ghost collide when they share a tile, or when they swap tiles within one tick.
- **Game speed** (user, 2026-10-01): the game is played at half speed. The rules count 30 ticks per game second (`Session.TICK_RATE`), and the server steps 15 steps per real second (`Session.STEP_RATE` = `TICK_RATE` × `GAME_SPEED` 0.5), so everything in game time takes twice as long in real time: level 1 is **3.75 tiles/s** (not 7.5), the turn buffer lasts 1.6 s, and the pauses and the frightened time will too. Slowing the clock leaves every tick-pinned rule and spec untouched. Camera turn smoothing (`View.TURN_SECONDS`) and mouse look stay in real time, which is the author's choice (user may veto): a key press now waits up to one step to take effect, about 67 ms instead of 33 ms.
- **Tick rate:** Logic runs on a fixed tick of **30 ticks per game second** (R0040) and is independent of frame rate. Clients interpolate.

## Scoring and rules (classic defaults; tune in (prep))
- **Points:** pellet 10, power pellet 50, ghosts 200/400/800/1600 within one power period.
- **Lives:** 3, and **one extra life, the first time the score reaches 10,000** (user, 2026-09-30; R0090). Once per run.
- **Eating slowdown** (user, 2026-09-30; R0090): eating stops the player as in the arcade: 1 frame of 60 fps for a dot, 3 for an energizer, at the level's speed (15 and 45 units at level 1, where a tile is 120 units and a tick is 30). The distance is owed and taken from the next steps; a death, a new level or a new run forgets it. **Deviation (R0090 design review round 2)**: the pause is *distance* at the speed of the tick that ate the pellet, so across a speed change it is up to a third of a frame off: an energizer (eaten at the normal speed, paid at the faster frightened one) stops the player about 2.65 frames rather than 3, and a dot eaten while frightened costs 17 units at level 1. Not visible (about 6 ms); the user can ask for frames-owed instead.
- **Levels:** clearing all pellets advances to the next level, which restores every pellet and puts the player back at the start. Speeds, the frightened duration and the mode schedule vary per level, following the classic tables; level 21 and on repeat the 21st row; frightened time is 0 on levels 17, 19, 20 and from 21 on, but 1 s on level 18 (R0090). **While frightened the player runs faster** (Table A.1, relative to level 1's 80%: levels 1 ×1.125, 2–4 ×1.1875, 5–20 ×1.25), user 2026-09-30. A death keeps the pellets already eaten.
- **Run pauses** (R0090, game time, 30 ticks per game second; double in real time): "Ready!" 2 s before play and after each death and level; death 1.5 s; level clear 2 s. Keys pressed in a pause are ignored.
- **Ghosts:** the four classic personalities.
  - Blinky targets the player's tile.
  - Pinky targets 4 tiles ahead.
  - Inky uses a vector from Blinky.
  - Clyde targets the player when more than 8 tiles away, and his scatter corner when closer.
  - Modes: scatter, chase and frightened. Ghosts never reverse, except when the mode changes. Ghosts are released from the ghost house by rule.
- **Fruit:** a non-goal for now.

## Hiscores
- **Boards:** all-time top N (N **(prep)**, e.g. 50), plus daily and weekly boards keyed by UTC period.
- **Entries:** the player's Roblox display name and user ID, the score and the level reached.
- **Submission:** only the server submits, from its own simulated result, at game over. Clients never send scores.
- **Storage:** behind a Logic-facing interface. A fake store is used in tests, and Roblox's ordered store in the adapter. Beta and production have separate stores, because they are separate experiences.

## Mobile
- **Turns:** a swipe left/right/down triggers `Left`/`Right`/`Back`, and a swipe up triggers `Forward`, to take the next junction's straight exit.
- **Look:** drag on the right half of the screen.
- **HUD:** scales to small screens. Touch targets are at least 44 pt.
- **Recentring:** a "snap look to heading" button.

## Open decisions
- **Danger awareness in first person** (f0320): minimap/radar, audio, edge indicators, vignette, or easier tables. The user decides before raft d's prep.

## Roadmap (single-type rafts; order a1 → a2 → b → c → c2 → d → e, with f any time after a2)
| Raft | Type | Issues | Proves |
|---|---|---|---|
| a1 Sim harness (R0030, done) | chore | c0090 | headless simulations and scenario specs in CI |
| a2 Barebones game (R0040, done) | feature | f0100, f0110, f0120, f0130 | a maze you can walk through in first person, in Studio |
| b Beta deploy (R0080) | chore | c0140, c0030 | a ready PR goes live on Beta, plus engine smoke tests |
| c Pellets & mechanics (R0090) | feature | f0150, f0160, f0170 | eating, score, lives, levels, power pellets: the rules, headless |
| c2 Presentation (R0150) | feature | f0180, f0290, f0300 | HUD, pellets drawn, start/game over/play again |
| d Ghosts (R0100) | feature | f0190, f0200, f0210, f0220, f0310, f0320 | classic ghost AI, its consequences, ghosts drawn, danger awareness |
| e Hiscores (R0110) | feature | f0230, f0240, f0250 | all-time, daily and weekly boards |
| f Mobile controls (R0120) | feature | f0260, f0270, f0280 | playable on a phone |

Process chores that aren't tied to a game raft: c0041 (worktrees, R0020), c0050, c0060, c0070 and c0080.
