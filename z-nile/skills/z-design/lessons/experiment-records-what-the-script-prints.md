---
title: An experiment records what its committed script prints
when: design
tags: [experiments, mutants, process]
check: Is each experiment's recorded result what the committed script prints when it is rerun as written (its command bounded by `./zn run`, in the environment the item's checks use), after the last edit to the code it reads?
---
An experiment's result is evidence only when someone can rerun the committed script and get it. A record written before the last formatting pass, or from a run in another environment, claims a pass the script no longer produces: an anchor the formatter split, or a variable the check strips and the script doesn't.

**Why:** c0286 design review 001 F6: E4 recorded "all 21 mutants killed", but stylua had split M7's anchor over several lines, so the committed `mutants.py` printed "M7: anchor not found once" and exited 1. Its command was a bare `python3`, not `./zn run --time`, and its environment kept `ZN_REAL_GIT` and `z-nile/bin` on `PATH`, which the item's `check.sh` strips.

**How to apply:** rerun every experiment script after the final format and edit, through `./zn run --time <s>`, in the same environment as the checks, and paste its actual output into the record.
