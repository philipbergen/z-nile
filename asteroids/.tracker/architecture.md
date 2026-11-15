# Asteroids architecture

c0184 scaffolds this home and c0185 gates code shared across homes. Shared code comes from the `arcade` library (`arcade/.tracker/architecture.md`). This file grows with the project's designs.

## Features

| feature | what it is | from |
|---|---|---|
| `Field` | the wrap-around field: wrapping, the shortest vector across the wrap, headings, a moving point's sweep against a circle | f0220 |
| `Ship` | one ship's flight: the fixed turn, thrust, drag and top speed | f0220 |
| `Rocks` | the three rock sizes, their points and speeds, and the split | f0220 |
| `Saucers` | the large and small saucer, their waits, crossing, course changes and aim | f0220 |
| `Pilot` | one player's ship and its life: on the field, in hyperspace or lost; protection, the respawn, the jump and its roll, the controls, the shots it fires, lives, score and extra lives | f0220 |
| `Classic` | one player's run: itself the player's `Pilot`, with the rocks, the saucer, the waves and the order of a tick | f0220 |

## Allowed dependencies

One `Consumer -> Provider` per line.

```deps
Ship -> Field
Rocks -> Field
Saucers -> Field
Pilot -> Field
Pilot -> Ship
Classic -> Field
Classic -> Pilot
Classic -> Ship
Classic -> Rocks
Classic -> Saucers
```
