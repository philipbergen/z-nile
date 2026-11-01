# Answers to design review 005 (f0147)

- F1: fixed: new case: seeds 1 to 40 on level 2, each played with long hops off and on, roll the same boon (at least three longer jumps among them); an Edge cases line states the rule; row M64 (one re-roll of a jumps roll while long hops are on), killed; M63 (the loop) still killed.
- F2: fixed: the carry case observes an eaten ghost's carry (a blue step, eaten, a step as eyes, blue again by hand: 12, not 13); row M65 (`Ghosts.eat` resets it) is `run`, killed; the reasoned row stays only for a reset when the eyes reach home.
