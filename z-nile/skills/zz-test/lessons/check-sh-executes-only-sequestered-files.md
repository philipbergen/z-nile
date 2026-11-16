---
title: A check.sh runs only files that are sequestered or pinned
when: design
tags: [check-sh, sequestration, experiments]
check: Does every file this check.sh executes or sources lie under `acceptance/` or inside check.sh itself, or carry a digest that check.sh pins, given that `experiments/` is not sequestered and executors write there?
---
The sequestration diff covers only `**/check.sh` and `**/acceptance/**`, so a criterion whose assertions live in `experiments/` can be turned green by editing that file, with no visible diff.

**Why:** c0185 design review 001 F1: AC6's assertions lived in `experiments/ac6.sh`. c0184's AC1 ran `experiments/places.luau` the same way (pinned by its sha256 since).

**How to apply:** inline the function in check.sh, or move it under `acceptance/`, or pin its sha256 in check.sh. Rerun c0120 `check-paths` and `finished` after any edit that moves code into check.sh.
