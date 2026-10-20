# Architecture map

These are the features in `src/shared/Logic/` and the directions they are allowed to depend on each other. `tests/meta/architecture.spec.luau` enforces this: every require from one feature to another must be listed below, and the list must not contain a cycle.

This file changes only through a `ticket-prep` design, never during execution unless that raft's design says so.

## Features

| Feature | Responsibility |
|---|---|
| Maze | The tile grid: built-in layouts, parsing and validation, tile kinds, passability per agent, neighbours with wrap, heading conventions (R0004, f0011) |
| Movement | Rail movement of one player through a Maze: sub-tile position, buffered turns, stops, Back, tunnels, tile entry (R0004, f0012) |
| Levels | The one table of per-level parameters: player speed factors, frightened time, flashes, and (R0010) the ghost speeds, the scatter/chase schedule, the house release limits and the slower-ghosts tuning factor; classic values (R0009, f0018; R0010) |
| Pellets | The pellets of one maze instance: what is left, eating, reset, points and the eating-pause distance (R0009, f0016) |
| Game | One player's run as a state machine: ready, playing, dying, level clear, game over; lives, level, score, extra life, the frightened counter (R0009, f0018; f0017) |
| Ghosts | The four classic ghosts of one maze instance as pure state: navigation and targets, the scatter/chase schedule and frightened mode, the ghost house and its release rules, contacts with the player, the classic layout's ghost data and the seeded generator they use (R0010, f0020 f0021 f0022 f0023); the eaten chain also restarts when the power runs out (R0035, f0100) |
| Awareness | How the player senses ghosts they cannot see, engine-free: the radar around the player and the edge indicators that grow and brighten as a ghost nears along the maze (R0010, f0033); the eight edge glows, their sectors and boxes (R0035, f0102) |
| Blaster | The ghost blaster's shots: the seeded drop when a ghost is eaten, at most three held, the fire intents, and which active ghost a shot along the grid hits (R0035, f0100) |
| Travel | Whether a player may be sent to another place now: one request at a time, a timeout, a cool-down after a failure, and validation of the configured destination place id (R0024, f0061) |
| Lobby | What the lobby screen shows, engine-free: the hiscore panel model (empty until the boards exist) and the start button for a travel status (R0024, f0061) |
| Hiscores | Period keys, the qualify rule, ranking and the top-N read of the all-time, daily and weekly boards. The store is a parameter; no other feature is required (R0011, f0024) |
| Session | One maze instance: players, validated and rate-limited intents, fixed-tick stepping, versioned snapshots, the server's fixed-step clock (R0004, f0013); fire intents, shots and drops (R0035, f0100) |
| Hud | What the heads-up display shows and how big: score, level, lives, power share; viewport layout, including an optional safe-area inset (R0015, f0019; R0012, f0029); the shot bars after the lives (R0035, f0100) |
| Flow | The overlay of each run phase: READY!, the dying fade, the level-clear flash, GAME OVER with the results and the way back to the lobby (R0015, f0031; R0034, f0065) |
| Touch | Touch zones and a pure fold over begin, move and end: one finger per zone, a straight-line swipe into one existing turn intent, look deltas in pixels, a snap hit (R0012, f0027, f0028, f0029) |
| View | First-person presentation math, engine-free: world scale, wall geometry, heading yaw, snapshot interpolation, turn smoothing, free look, key map (R0004, f0014); pellet placement and pulse (R0015, f0030); the lowered walls, the ghost body and the jump (R0035, f0101), the ghost colours and the beam's end (f0100, f0102), the new keys, the arrow look and the shot's aim (f0104) |

Hiscores has no row in the deps block. It takes the store as a parameter. Session, Lobby and Flow do not require it; the server and lobby adapters call it (R0011).

## Allowed dependencies

One `Consumer -> Provider` per line.

```deps
Awareness -> Maze
Blaster -> Maze
Flow -> Game
Flow -> Session
Flow -> Travel
Game -> Levels
Ghosts -> Levels
Ghosts -> Maze
Ghosts -> Movement
Hud -> Levels
Hud -> Session
Lobby -> Travel
Movement -> Maze
Pellets -> Maze
Session -> Blaster
Session -> Game
Session -> Ghosts
Session -> Levels
Session -> Maze
Session -> Movement
Session -> Pellets
Touch -> View
View -> Maze
View -> Movement
View -> Pellets
View -> Session
```
