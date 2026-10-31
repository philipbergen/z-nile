# Answers to design review 002 (f0147)

- F1: fixed: the carry is ½ whenever a ghost is placed (`newGhost`, so a new level, a new run and a death), so each first fractional step is the rate rounded: Blinky's first tunnel step is 10 again and f0032's promoted frame case passes (8/8 on the prototype). The full pickman gate is rerun on the prototype after the change (E9). New case (the ½ start, and again after a death); row M53 (started at 0), killed. Consequences: the carry's other properties are now stated (each ghost's own field; kept across a change of kind) and pinned (F3).
- F2: fixed: two sub-cases read the threshold from the start with the level different (start 1 on level 3: 10,000; start 2 on level 5: 20,000); row M51 (`× g.level`), killed. Lesson zz-test/set-read-fields-apart.
- F3: fixed: Behaviour 2 states the carry is a field of each ghost's record (never shared between sets), ½ when placed, kept across a change of kind; a case steps two sets in turn and requires each step to equal a lone set's, and a case resets after three steps; row M54 (one carry per name, shared), killed.
- F4: fixed: a wasted pick (a movement key mid-pick: `PickStopped moved`) leaves the count at 0, and the next finished pick makes it 1; row M52 (counted when a pick starts), killed. Behaviour 4 says only a finished pick counts.
- F5: fixed: Behaviour 2 says the eyes are strictly faster up to level 22 and capped at a tile from 23.
- F6: fixed: `Levels.MAX_TOP = 1000`; `validateRamp` refuses a top over it (case: top 1001 refused by Levels and by `Session.new`); row M55, killed.
- F7: fixed: c0177's Solution retitles the narrowed eyes case (the shipped eyes are the untuned config's).
