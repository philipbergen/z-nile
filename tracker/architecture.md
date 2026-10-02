# Architecture map

These are the features in `src/shared/Logic/` and the directions they are allowed to depend on each other. `tests/meta/architecture.spec.luau` enforces this: every require from one feature to another must be listed below, and the list must not contain a cycle.

This file changes only through a `ticket-prep` design, never during execution unless that raft's design says so.

## Features

| Feature | Responsibility |
|---|---|
| Maze | The tile grid: built-in layouts, parsing and validation, tile kinds, passability per agent, neighbours with wrap, heading conventions (R0040, f0100) |
| Movement | Rail movement of one player through a Maze: sub-tile position, buffered turns, stops, Back, tunnels, tile entry (R0040, f0110) |
| Levels | The one table of per-level parameters: player speed factors, frightened time, flashes, and (R0100) the ghost speeds, the scatter/chase schedule, the house release limits and the slower-ghosts tuning factor; classic values (R0090, f0170; R0100) |
| Pellets | The pellets of one maze instance: what is left, eating, reset, points and the eating-pause distance (R0090, f0150) |
| Game | One player's run as a state machine: ready, playing, dying, level clear, game over; lives, level, score, extra life, the frightened counter (R0090, f0170; f0160) |
| Ghosts | The four classic ghosts of one maze instance as pure state: navigation and targets, the scatter/chase schedule and frightened mode, the ghost house and its release rules, contacts with the player, the classic layout's ghost data and the seeded generator they use (R0100, f0190 f0200 f0210 f0220) |
| Awareness | How the player senses ghosts they cannot see, engine-free: the radar around the player and the edge indicators that grow and brighten as a ghost nears along the maze (R0100, f0320) |
| Travel | Whether a player may be sent to another place now: one request at a time, a timeout, a cool-down after a failure, and validation of the configured destination place id (R0240, f0670) |
| Lobby | What the lobby screen shows, engine-free: the hiscore panel model (empty until the boards exist) and the start button for a travel status (R0240, f0670) |
| Session | One maze instance: players, validated and rate-limited intents, fixed-tick stepping, versioned snapshots, the server's fixed-step clock (R0040, f0120) |
| Hud | What the heads-up display shows and how big: score, level, lives, power share; viewport layout (R0150, f0180) |
| Flow | The overlay of each run phase: READY!, the dying fade, the level-clear flash, GAME OVER and the play-again prompt and keys (R0150, f0300) |
| View | First-person presentation math, engine-free: world scale, wall geometry, heading yaw, snapshot interpolation, turn smoothing, free look, key map (R0040, f0130); pellet placement and pulse (R0150, f0290) |

## Allowed dependencies

One `Consumer -> Provider` per line.

```deps
Awareness -> Maze
Flow -> Game
Flow -> Session
Game -> Levels
Ghosts -> Levels
Ghosts -> Maze
Ghosts -> Movement
Hud -> Levels
Hud -> Session
Lobby -> Travel
Movement -> Maze
Pellets -> Maze
Session -> Game
Session -> Ghosts
Session -> Levels
Session -> Maze
Session -> Movement
Session -> Pellets
View -> Maze
View -> Movement
View -> Pellets
View -> Session
```
