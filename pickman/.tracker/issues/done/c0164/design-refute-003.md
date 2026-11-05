# c0164 design refute 003

- F1: fixed, by the rule the review stated ("the colour state depends on frame.play alone, in every phase") rather than by naming fields: one script of play states runs twice, on bare frames and on busy frames carrying every other Frame field (holes and marks, a ghost, shots, a shot, a hop, a pick, a boon), each changing per frame, at odd and even ticks, with a named check that the busy frames differ from the bare ones; ready frames added. consequences: mutants B1, W1, H1, GH, K1, K1r, R1 and TK added, run, killed; every earlier result unchanged (base 11, N3 OTHER, P4/C1/C2 green in views.spec); `views.patch` and walls.spec's digest regenerated.
- F2: fixed: the script follows the game's order: a ready before each life, lives only going down, the level only going up. consequences: none beyond F1's.
- F3: fixed: `mutants.py` records the SHA-256 of f0126's `prototype.patch` and of its acceptance specs and refuses when either changed (it ran: not refused today). consequences: none.
- F4: fixed: review 002's second candidate lesson is placed as a note on zz-test/source-pins-name-what-the-design-names, with a `- note` line in harvest.md. consequences: none.
