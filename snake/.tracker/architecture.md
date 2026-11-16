# Snake architecture

c0184 scaffolds this home and c0185 gates code shared across homes. Shared code comes from the `arcade` library (`arcade/.tracker/architecture.md`). This file grows with the project's designs.

## Features
| feature | path | what it is | from |
|---|---|---|---|
| Maps | `src/shared/Logic/Maps` | the arena of each map: its side for N players, its speed and goal, the spawns, and the seeded roll of its walls (map k has k-1 walls that never connect) | f0211 |
| World | `src/shared/Logic/World` | the rules of one arena of N snakes: movement with two buffered turns, apples and growth, deaths, lives and respawn, and the map progression | f0211 |

Randomness reaches both as a `Draw` parameter (`(n) -> number`, a whole number in 1..n), the shape of arcade's `Rng.draw` (f0203): Logic never requires arcade, and the server's session (f0213) builds the draw.

## Allowed dependencies

One `Consumer -> Provider` per line.

```deps
World -> Maps
```
