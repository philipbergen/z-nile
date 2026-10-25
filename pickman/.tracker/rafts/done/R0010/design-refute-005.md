# Refutations 005: R0010 (design mode)

- F1: fixed: a case sweeps a ghost's x between tiles (along the open row 5, and through the wrap at 27.3, 27.7 and -0.3) and asserts the exact bearing; the Rules and mutants row is split into "the player's fraction ignored" and "the ghost's fraction ignored", both run and killed by assertion. Consequences: none beyond the rows.
- F2: fixed: the radar's walls are shifted by the player's fraction (`turn(dx - frac(pose.x), dy - frac(pose.y))`), so walls and blips share an origin; a case with the player at (6.4, 5) pins a wall at (-1.4, -1) and a blip at 0.6; mutant "radar walls ignore the fraction" killed. Consequence: the radar content now changes every frame (it already did through the blips), still only a few hundred numbers.
- F3: fixed: f0033's Test plan lists the round-4 and round-5 cases, f0023's the revived-ghost case, and f0033's API declares `Awareness.Blip` and `Awareness.Radar` as exported types with `radar(...): Radar`.
