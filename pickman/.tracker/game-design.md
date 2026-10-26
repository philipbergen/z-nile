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
| Hiscores | A **global all-time top N**, plus **daily** and **weekly** boards. No personal-best feature for now, except the lobby's "your best" line under the all-time board (user, 2026-10-21, d0124). The all-time board also keeps a top-10 list of runs (see Hiscores). |
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
- **Desktop keys** (user, 2026-10-17; f0104, R0035): **W** `Forward` (the straight exit, and it cancels a buffered turn), **A** `Left`, **D** `Right`, **S** `Back`, as before. **Space** jumps (the spy hop, f0101). **E** fires the blaster (f0100). **F** picks a marked wall (f0126; user, 2026-10-25: "A new pick key"). The **arrow keys look** relative to the direction of travel while held (up ahead, down behind, left and right to the sides, two together give the diagonals) and the view springs back to the heading on release; pressing an arrow also snaps the view out of any mouse look. The snap-look key goes away.
- **Collisions are grid rules in Logic:**
  - wall contact means stopping at the tile edge: the player is one tile wide, so its front edge meets the wall when its centre reaches the last tile's centre (R0004);
  - pellets are eaten when the player enters a tile;
  - player and ghost collide when they share a tile, or when they swap tiles within one tick.
- **Game speed** (user, 2026-10-01): the game is played at half speed. The rules count 30 ticks per game second (`Session.TICK_RATE`), and the server steps 15 steps per real second (`Session.STEP_RATE` = `TICK_RATE` × `GAME_SPEED` 0.5), so everything in game time takes twice as long in real time: level 1 is **3.75 tiles/s** (not 7.5), the turn buffer lasts 1.6 s, and the pauses and the frightened time will too. Slowing the clock leaves every tick-pinned rule and spec untouched. Camera turn smoothing (`View.TURN_SECONDS`) and mouse look stay in real time, which is the author's choice (user may veto); the spy hop does not, since it decides catches (f0101, 2026-10-21): it is counted in steps, and its real-time numbers follow `GAME_SPEED`. Every intent also follows the clock: a key press now waits up to one step to take effect, about 67 ms instead of 33 ms. Limits counted in steps follow the clock: at most 4 intents per step is 60 intents per real second, and the 5-step catch-up cap after a hitch is 1/3 s of real time.
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
- **Top-10 runs (2026-10-21, d0124):** besides each player's best row on every board, the all-time board keeps one list of the ten best runs of all players, so one player can hold several places (rows: 10 plus one per player). Only all-time has it; today and this week stay one best row per player. Game over shows the run's place on that list, or that it is not in the all-time top 10. The lobby's all-time panel lists those ten runs and ends with the viewer's own best: the one personal-best line, by the user's choice. Rows stored before the list existed start it, one entry each. (R0044)
- **Storage:** behind a Logic-facing interface. A fake store is used in tests, and Roblox's ordered store in the adapter. Beta and production have separate stores, because they are separate experiences.

## Mobile
- **Turns:** a swipe left/right/down triggers `Left`/`Right`/`Back`, and a swipe up triggers `Forward`, to take the next junction's straight exit.
- **Look:** drag on the right half of the screen.
- **HUD:** scales to small screens. Touch targets are at least 44 pt.
- **Recentring:** a "snap look to heading" button.

## Ghost hunter tools (user, 2026-10-17; R0035)
The user's captures (f0100, f0101, f0102), with the details chosen in R0035's prep marked **(prep)**; the user may veto any of those.
- **Blaster** (f0100): eating a ghost has a chance of granting one blaster shot (default 50%, a tuning constant to set after a Beta playtest); at most three are held and a drop while holding three is wasted; firing spends one; a hit ghost behaves exactly like an eaten one (the next value in the chain, eyes home, harmless until it has revived). The shot is two-dimensional along the maze grid, the way the player looks, rounded to the nearest heading (the arrows' direction when one is held). The roll is seeded on the server. The power pellet stays as it is. **(prep)**: the blaster works any time in play; a miss is spent; the shot is instant along its row or column, stopped by walls, doors and the house, carried round the side tunnel once; the first active ghost on the line is hit (eyes and ghosts in the house are passed through); only a contact eat rolls for a drop; the chain also restarts when the power runs out; shots outlive a death and a level and are gone on a new run; a fire in a pause does nothing; the shot starts from the tile the server has the player on before that step's move, with no grace, so with ordinary latency (about 100 ms round trip) a shot into a side corridor must be pressed about half a tile before the junction's centre as the player sees it; the drops follow the session seed (the player's user id today), so a player's n-th eaten ghost rolls the same in every game; the HUD shows one cyan bar per shot after the lives, on touch too until a touch fire control exists (f0110); a shot the server took shows a short cyan beam.
- **Spy hop** (f0101): slightly lower walls, ghosts keep the walls' old height (10) and stand above them, and a jump raises the camera over the walls for a short time with a short cooldown; the rail goes on underneath. **Jumping over ghosts** (user, 2026-10-21): "we want to be able to jump to look around, AND to jump over ghosts". The player is airborne only while the eye is above the wall tops (the middle of the jump), and while airborne no ghost catches them, a blue ghost is passed over and not eaten, and pellets passed over are not eaten; the cooldown stays 0.5 s. **(prep)**: walls 9 studs; the eye rises 14 studs and lands in 12 steps (800 ms of real time); airborne the 2nd to the 11th step of it (667 ms; each step judged at its middle). The step rule is off the drawn eye by at most 0.19 of a step, in the player's favour; the next jump 8 steps (533 ms) after landing. The server decides the hop (the `Hop` intent) and the camera shows it.
- **Glows** (f0102): the edge arrows give way to glows in eight places on the screen (the edges' middles and the corners), coloured as the ghost, in its direction from where the camera looks, and brighter as it nears; the radar stays. **(prep)**: every ghost within 12 tiles along the maze glows, in view or not (eyes excepted); the nearest in a direction lights it; a glow is at most 12% of the screen's smaller side, in the device's safe area, under the radar, the overlays and the HUD.
- **Keys**: see *Desktop keys* (f0104). **(prep)**: the arrow look turns at the camera's turn rate and springs back the same way; two arrows that tie aim the way of travel.

## Wall picks (user, 2026-10-25; f0126)
The user's words: "tick should take the time it takes for a ghost to move 10 paces, only interior walls with special color and there are only ever 2-3 of them after you pick one it new interior wall will become picked, even chance on each boon", and "Another boon should be all pills eaten come back". Then, asked: one tile per pick ("One tile only"), "Always 3", "A new pick key", "Gold", the boon defaults below ("Use these defaults"), and the pellets boon brings back "Dots and power pellets".
- **Marked walls:** three interior walls (not on the maze's outer edge) at a time are gold; a finished pick marks the next at once.
- **Every input** (user, 2026-10-25: "We support keyboard, cosole, and touch for every feature"): the pick is asked for on the keyboard, a controller and a touch screen alike.
- **The pick:** F asks for one (on a controller Y / triangle, `ButtonY`, a row of f0146's controller map; on touch a PICK button one margin left of FIRE, level with it and its size, added after f0110, which on narrow portrait phones takes a 70 px square of the swipe-to-turn half: user, 2026-10-25; the pick works on every input, the user's rule); the player stops on the next tile centre beside a marked wall and stands there as long as a ghost takes to move 10 paces (the user's words; **(prep)**: a hunting ghost walking 10 tiles at its speed on that level) (43 steps on level 1, 2.9 s of real time, at today's ghost speed; ten paces of the ghosts as tuned, so 47 steps with f0125's slower ghosts). A movement key, a hop, or leaving play (a death, a cleared level) wastes it. A finished pick opens that one wall tile, for the player and the ghosts, and the player goes on.
- **The gold** is 255, 215, 0 (user, 2026-10-26: "Brighter gold"), at least 30 CIE76 from every ghost colour (Clyde 33.3, Inky 31.4).
- **Marked walls stay gold** while the walls are green (f0109; user, 2026-10-25: "Stay gold"); the level-clear flash still lights them white.
- **Boons**, each with the same chance (1 in 6): **longer jumps** (every hop airborne 1.5 times as long, until the maze is fresh again), a **faster pick** (the next pick that finishes takes half the time), a **ghost pill** (a power pellet's frightened time), a **long ghost pill** (twice that), a **blaster shot** (one more, wasted when three are held) and **pellets back** (every eaten pellet and power pellet reappears).
- **(prep)**, the user may veto any: a wall can be marked only when no door or house tile is among its eight neighbours (the ghost house stays shut) and the player can walk next to it, and the marks are a seeded roll among those walls; a ghost that catches a picking player wastes the pick, and a blue ghost met while picking is eaten without wasting it; the HUD's power bar is the share of a power pellet's time, so it stays full for the first half of a long ghost pill; the long hop is 19 steps (airborne 15 against a hop's 10, the same 14-stud rise, the same 8-step cool-down after landing); a pick request stays pending as long as a buffered turn (24 steps) and one pressed during a pick is ignored; no pick starts while a hop is under way; the wall picked from a tile is the marked one ahead, then left, right, behind; the pick that ends this step finishes before that step's keys, and the player sets off in the same step; firing does not waste a pick; a death keeps the holes and the marks, while a new level or a new run closes the holes and rolls new marks; banked faster picks last until a new run, and a wasted pick keeps its faster pick; the marks and the boons follow the session seed, as the blaster's drops do (the open drop-seed decision applies to them too); the HUD shows a gold bar for the pick under way and the boon's name for 2 s; the radar shows the holes but not the marks.

## Open decisions
- **The blaster's drop chance** (f0100): a number for `Blaster.DROP_PERCENT` (50 until then), after a Beta playtest.
- **A shot grace at junctions** (R0035 prep): keep the shot from the server's tile (the (prep) default above), or add a short grace so a side shot pressed on a junction the player sees still goes up the side corridor (a later issue).
- **The drop seed** (R0035 prep): keep seeding by the player's user id (a player's n-th eaten ghost rolls the same every game), or seed each session freshly in the server (which also varies the frightened ghosts' wander).
- **The shot bars on touch** (R0035 prep): shown until f0110 gives touch a fire control, or hidden until then.
- **Inky's colour** (f0109): Inky's body (and, with R0035, its glow) is `(0, 255, 255)`, which the user sees as white; a new colour is wanted but not chosen.
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
