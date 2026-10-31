# Refute 004: c0139 (design mode)

- F1: fixed: case (d) now calls `outsideRepo` directly on the plain copy with each of the four git location variables set alone (expecting inside) and with none (expecting outside). Mutant W2b, each name dropped from `GIT_VARIABLES` in turn, is killed four times; the W2 row names it; consequences: none.
- F2: fixed: implementation step 5 adds repo-fence's `ALLOWED` entry for the promoted conflicts.spec before `done`, while the item is active (the stale-key case accepts it then); the Where bullet says it can't land only in the prototype; consequences: none.
