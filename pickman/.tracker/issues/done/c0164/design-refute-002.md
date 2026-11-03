# c0164 design refute 002

- F1: fixed: every frame now sets every field its producer's transition writes (phase, timer, frightened, lives, level, score), and four frames are added: `frightened` 1 (the lowest edible tick) on level 2, the last life lost under power (`lives` 1, then a death with `lives` 0) and game over. consequences: mutants G1 (lives guard), G2 (game-over guard), L1 (level guard), T1 and T2 (walls' cutoffs above 0) and T1r (the radar's) added, run, killed; base, P4, C1 and C2 unchanged; `views.patch` and walls.spec's digest regenerated.
- F2: fixed: Scalability says fourteen frames. consequences: none.
