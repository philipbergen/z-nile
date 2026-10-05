# Refutations 001: R0010 (code mode)

- F1: fixed: `tests/unit/Awareness` pins that size and brightness follow the distance along the maze: the player at (12,1) facing south and a ghost at (15,1) behind the top-middle wall get distance 11 and the size and brightness of 11 tiles, against an arrow for a ghost 3 tiles away in an open corridor that is bigger.
- F2: fixed: a `tests/unit/Ghosts` case pins that a ghost leaves the house heading west, and a `tests/unit/Session` case pins that a session seeds its ghosts from its own seed (same seed, same generator state; another seed, another).
- F3: fixed: `Levels.schedule` is memoised per level and tick rate and returns a frozen table (a unit case pins it); the step no longer builds a table every tick.
