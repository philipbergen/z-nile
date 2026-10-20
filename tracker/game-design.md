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
| Two places (2026-10-02) | The experience has two places. The **lobby** (the existing place, the experience's start place) shows a hiscore list and a START GAME button, and a click teleports the player to the **game place**, which hosts the actual game. At game over an overlay shows the results and waits for a tap, then teleports back to the lobby (f0065, after c0063). The hiscore list is an empty panel until R0011 fills it. Both places live in the Beta experience (a repo variable for the game place's id); production stays undecided. (R0024, f0061; c0064) |
| Deploy | A separate, private **Pickman Beta** experience. Every PR that becomes ready for review is published there (last one wins). Production publishing will be decided later. |
| Hiscores | A **global all-time top N**, plus **daily** and **weekly** boards. No personal-best feature for now. |
| Platforms | Desktop (keyboard and mouse) and **mobile (touch)**. Gamepad isn't planned; it gets the same intents if it's added later. |
| Danger awareness (2026-10-01) | **A minimap/radar and edge indicators** show where ghosts are in first person. The indicators give a sense of distance, not just direction: bigger and brighter as the ghost gets closer (R0010, f0033). Audio and a proximity vignette were not chosen. |
| Slower ghosts (2026-10-01) | Ghosts may be slower than the classic tables, through **one tuning factor** (`Levels.GHOST_TUNING`) on the hunting and frightened ghost speeds, not on eyes. It ships at the classic 1 until the user gives the factor, after a Beta playtest (R0010, f0021). |

## Movement model: rail with free look
**All durations and speeds in this document are game time** (30 ticks per game second); the game is played at half speed, so real time is twice as long (see *Game speed* below).

- **The maze is a grid of tiles.** Walls are whole tiles. Walkable tiles form corridors, and a junction is a tile with more than 2 exits.
- **Movement:**
  - The player always moves along the current corridor at the level's speed and stops at a wall. Level 1 is **7.5 tiles/s of game time** (3.75 in real time, see Game speed), the arcade's 80% (R0004). Per level (R0009, *Pac-Man Dossier* Table A.1, relative to level 1): levels 2–4 ×1.125, 5–20 ×1.25, 21 and on ×1.125, in whole units per tick (30, 34, 38, 34).
  - **Corners are classic** (decided by the user, 2026-09-29): at a corner the player stops unless a turn into it is buffered. There is no automatic cornering.
  - There is no free strafing; position is always on a corridor centreline.
- **Turn intents:** `Left`, `Right`, `Back` and `Forward`, relative to the current heading.
  - A turn intent is **buffered** and taken at the next tile where that exit exists.
  - `Back` reverses immediately: a literal reverse of the current heading, as in the arcade, even right after a turn (user, 2026-09-29).
  - The buffer expires after **0.8 s of game time** (24 ticks; R0004), 1.6 s in real time. A re-press restarts it.
  - **Cornering grace** (user, 2026-09-29): a turn arriving one tick after passing straight through a centre where that exit exists is taken there, cutting the corner.
  - **Missed turns** (user, 2026-09-29): a later press for a turn the player just passed straight by is discarded while the player is still nearer that junction than the next one ahead with that exit, so a late press never diverts the player at a later junction. A press nearer the next such junction is buffered for it.
- **Look:** the camera's yaw and pitch are free and never change the heading. On desktop the arrow keys look relative to the heading (see *Desktop keys*); on touch a "snap look to heading" button recentres it.
- **Desktop keys** (user, 2026-10-17; f0104, R0035): **W** `Forward` (the straight exit, and it cancels a buffered turn), **A** `Left`, **D** `Right`, **S** `Back`, as before. **Space** jumps (the spy hop, f0101). **E** fires the blaster (f0100). The **arrow keys look** relative to the direction of travel while held (up ahead, down behind, left and right to the sides, two together give the diagonals) and the view springs back to the heading on release; pressing an arrow also snaps the view out of any mouse look. The snap-look key goes away.
- **Collisions are grid rules in Logic:**
  - wall contact means stopping at the tile edge: the player is one tile wide, so its front edge meets the wall when its centre reaches the last tile's centre (R0004);
  - pellets are eaten when the player enters a tile;
  - player and ghost collide when they share a tile, or when they swap tiles within one tick.
- **Game speed** (user, 2026-10-01): the game is played at half speed. The rules count 30 ticks per game second (`Session.TICK_RATE`), and the server steps 15 steps per real second (`Session.STEP_RATE` = `TICK_RATE` × `GAME_SPEED` 0.5), so everything in game time takes twice as long in real time: level 1 is **3.75 tiles/s** (not 7.5), the turn buffer lasts 1.6 s, and the pauses and the frightened time will too. Slowing the clock leaves every tick-pinned rule and spec untouched. Camera turn smoothing (`View.TURN_SECONDS`) and mouse look stay in real time, which is the author's choice (user may veto): a key press now waits up to one step to take effect, about 67 ms instead of 33 ms. Limits counted in steps follow the clock: at most 4 intents per step is 60 intents per real second, and the 5-step catch-up cap after a hitch is 1/3 s of real time.
- **Tick rate:** Logic runs on a fixed tick of **30 ticks per game second** (R0004) and is independent of frame rate. Clients interpolate.

## Scoring and rules (classic defaults; tune in (prep))
- **Points:** pellet 10, power pellet 50, ghosts 200/400/800/1600 within one power period.
- **Lives:** 3, and **one extra life, the first time the score reaches 10,000** (user, 2026-09-30; R0009). Once per run.
- **Eating slowdown** (user, 2026-09-30; R0009): eating stops the player as in the arcade: 1 frame of 60 fps for a dot, 3 for an energizer, at the level's speed (15 and 45 units at level 1, where a tile is 120 units and a tick is 30). The distance is owed and taken from the next steps; a death, a new level or a new run forgets it. **Deviation (R0009 design review round 2)**: the pause is *distance* at the speed of the tick that ate the pellet, so across a speed change it is up to a third of a frame off: an energizer (eaten at the normal speed, paid at the faster frightened one) stops the player about 2.65 frames rather than 3, and a dot eaten while frightened costs 17 units at level 1. Not visible (about 6 ms); the user can ask for frames-owed instead.
- **Levels:** clearing all pellets advances to the next level, which restores every pellet and puts the player back at the start. Speeds, the frightened duration and the mode schedule vary per level, following the classic tables; level 21 and on repeat the 21st row; frightened time is 0 on levels 17, 19, 20 and from 21 on, but 1 s on level 18 (R0009). **While frightened the player runs faster** (Table A.1, relative to level 1's 80%: levels 1 ×1.125, 2–4 ×1.1875, 5–20 ×1.25), user 2026-09-30. A death keeps the pellets already eaten.
- **Run pauses** (R0009, game time, 30 ticks per game second; double in real time): "Ready!" 2 s before play and after each death and level; death 1.5 s; level clear 2 s. Keys pressed in a pause are ignored.
- **Ghosts:** the four classic personalities (R0010: details below).
  - Blinky targets the player's tile.
  - Pinky targets 4 tiles ahead.
  - Inky uses a vector from Blinky.
  - Clyde targets the player when more than 8 tiles away, and his scatter corner when closer.
  - Modes: scatter, chase and frightened. Ghosts never reverse, except when the mode changes. Ghosts are released from the ghost house by rule.
  - **Details chosen in R0010's prep (the user may veto any):** ghosts decide at tile centres and take the exit closest in a straight line to their target (ties: up, left, down, right), with the arcade's no-up junctions; Pinky and Inky aim exactly ahead of the player, **without the arcade's overflow bug** when the player faces up; **Cruise Elroy is not built**; ghost speeds follow Table A.1 rounded to whole sub-tile units (level 1: 28 units a tick against the player's 30), slower in the side tunnels and while frightened; the timetable is Table A.2 and stops while the ghosts are blue; frightened ghosts turn back once, then wander at random (seeded, **uniformly among the open exits**; the arcade's choice is slightly biased), and **blink for the last `flashes` flashes of 14 ticks** (7 blue, 7 white); **eyes run at twice level 1's player speed**; houses release by personal counters (Pinky 0; Inky 30 on level 1, 0 later; Clyde 60, 50, 0), an idle timer (4 s, 3 s from level 5) and a global counter after a death (7, 17, 32); a kill beats an eating in the same tick and a cleared level beats a kill; **an eaten ghost comes out of the house dangerous (not blue) for the rest of that power period**, as in the arcade; a power pellet eaten on the tile a ghost reaches in the same tick makes it blue before the contact (so it is eaten); a blue ghost met on the very tick the blue time ends kills; the end of the blue time does not turn ghosts back; **there is no pause when a ghost is eaten and no score pop-up where it was eaten** (the arcade freezes the game for about a second; the user may ask for it).
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

## Ghost hunter tools (user, 2026-10-17; R0035)
The user's captures (f0100, f0101, f0102), with the details chosen in R0035's prep marked **(prep)**; the user may veto any of those.
- **Blaster** (f0100): eating a ghost has a chance of granting one blaster shot (default 50%, a tuning constant to set after a Beta playtest); at most three are held and a drop while holding three is wasted; firing spends one; a hit ghost behaves exactly like an eaten one (the next value in the chain, eyes home, harmless until it has revived). The shot is two-dimensional along the maze grid, the way the player looks, rounded to the nearest heading (the arrows' direction when one is held). The roll is seeded on the server. The power pellet stays as it is. **(prep)**: the blaster works any time in play; a miss is spent; the shot is instant along its row or column, stopped by walls, doors and the house, carried round the side tunnel once; the first active ghost on the line is hit (eyes and ghosts in the house are passed through); only a contact eat rolls for a drop; the chain also restarts when the power runs out; shots outlive a death and a level and are gone on a new run; a fire in a pause does nothing; the HUD shows one cyan bar per shot after the lives, and a shot shows a short cyan beam.
- **Spy hop** (f0101): slightly lower walls, ghosts keep the walls' old height (10) and stand above them, and a jump raises the camera over the walls for a short time with a short cooldown; the jump is a camera offset only (the rail goes on underneath, and the player can still be caught). **(prep)**: walls 9 studs; the eye rises 14 studs and lands in 0.8 s of real time, and may jump again 0.5 s after landing.
- **Glows** (f0102): the edge arrows give way to glows in eight places on the screen (the edges' middles and the corners), coloured as the ghost, in its direction from where the camera looks, and brighter as it nears; the radar stays. **(prep)**: every ghost within 12 tiles along the maze glows, in view or not (eyes excepted); the nearest in a direction lights it; a glow is at most 12% of the screen's smaller side, under the HUD and in the device's safe area.
- **Keys**: see *Desktop keys* (f0104). **(prep)**: the arrow look turns at the camera's turn rate and springs back the same way; two arrows that tie aim the way of travel.

## Open decisions
- **The blaster's drop chance** (f0100): a number for `Blaster.DROP_PERCENT` (50 until then), after a Beta playtest.
- **The slower-ghosts factor** (f0021): a number for `Levels.GHOST_TUNING`, after a Beta playtest of the classic tables with the radar and the edge indicators.

## Roadmap (single-type rafts; order a1 → a2 → b → c → c2 → d → e, with f any time after a2)
| Raft | Type | Issues | Proves |
|---|---|---|---|
| a1 Sim harness (R0003, done) | chore | c0010 | headless simulations and scenario specs in CI |
| a2 Barebones game (R0004, done) | feature | f0011, f0012, f0013, f0014 | a maze you can walk through in first person, in Studio |
| b Beta deploy (R0008) | chore | c0015, c0003 | a ready PR goes live on Beta, plus engine smoke tests |
| c Pellets & mechanics (R0009) | feature | f0016, f0017, f0018 | eating, score, lives, levels, power pellets: the rules, headless |
| c2 Presentation (R0015) | feature | f0019, f0030, f0031 | HUD, pellets drawn, start/game over/play again |
| d Ghosts (R0010) | feature | f0020, f0021, f0022, f0023, f0032, f0033 | classic ghost AI, its consequences, ghosts drawn, danger awareness (radar and edge indicators) |
| e Hiscores (R0011) | feature | f0024, f0025, f0026 | all-time, daily and weekly boards |
| f Mobile controls (R0012) | feature | f0027, f0028, f0029 | playable on a phone |
| g Lobby place (R0024) | feature | f0061 | a lobby place with a start button that teleports to the game place (any time; the Beta publish is c0064, the way back f0065) |
| h Ghost hunter tools (R0035) | feature | f0100, f0101, f0102, f0104 | a blaster whose shots drop from eaten ghosts, a spy hop over lower walls, eight-direction ghost glows, the new desktop keys (after c0103) |

Process chores that aren't tied to a game raft: c0005 (worktrees, R0002), c0006, c0007, c0008 and c0009.
