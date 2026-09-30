# Architecture map

These are the features in `src/shared/Logic/` and the directions they are allowed to depend on each other. `tests/meta/architecture.spec.luau` enforces this: every require from one feature to another must be listed below, and the list must not contain a cycle.

This file changes only through a `ticket-prep` design, never during execution unless that raft's design says so.

## Features

| Feature | Responsibility |
|---|---|
| Maze | The tile grid: built-in layouts, parsing and validation, tile kinds, passability per agent, neighbours with wrap, heading conventions (R0040, f0100) |
| Movement | Rail movement of one player through a Maze: sub-tile position, buffered turns, stops, Back, tunnels, tile entry (R0040, f0110) |
| Session | One maze instance: players, validated and rate-limited intents, fixed-tick stepping, versioned snapshots, the server's fixed-step clock (R0040, f0120) |
| View | First-person presentation math, engine-free: world scale, wall geometry, heading yaw, snapshot interpolation, turn smoothing, free look, key map (R0040, f0130) |

## Allowed dependencies

One `Consumer -> Provider` per line.

```deps
Movement -> Maze
Session -> Maze
Session -> Movement
View -> Maze
View -> Movement
View -> Session
```
