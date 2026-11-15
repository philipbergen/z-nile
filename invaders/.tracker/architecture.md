# Invaders architecture

c0184 scaffolds this home and c0185 gates code shared across homes. Shared code comes from the `arcade` library (`arcade/.tracker/architecture.md`). This file grows with each design.

## Features
| feature | what it is | issue |
|---|---|---|
| `Logic/Formation` | the 5 x 11 aliens and their march (step, advance, reverse, the wait read from the live count) | f0216 |
| `Logic/Barriers` | the four bunkers of 8 x 6 blocks, eroded by shots from either side and erased by aliens | f0216 |
| `Logic/Mystery` | the ship across the far end: its timer, its crossing and its value table | f0216 |
| `Logic/Classic` | one player's game: cannon, shots, lives, score, waves, invasion and the revive's restart; composes the three above | f0216 |

The field is 2-D (game-design.md, The field and view): `x` across, `d` the depth from the base line (the cannon's line, `d = 0`) to the far end, in whole field units. The view (f0218) maps `x` and `d` to the world.

## Allowed dependencies

One `Consumer -> Provider` per line.

```deps
Classic -> Formation
Classic -> Barriers
Classic -> Mystery
```
