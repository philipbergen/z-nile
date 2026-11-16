---
title: A check is proven as `done` runs it, after the raft's own steps
when: design
tags: [check-sh, acceptance, promotion]
check: Was every check.sh line and acceptance spec run in the layout `done` sees (the specs still in the issue's acceptance/ folder, the raft's own code review and refute already committed), and does each still pass there?
---
A criterion proven in a layout that never occurs during execution passes in prep and fails at `done`. `done` runs `check.sh` before it promotes the specs and after the raft's own review files are committed.

**Why:** c0112 design review 001 (F1, F2): AC6 counted the raft's own `review-NNN.md` and `refute-NNN.md` as "changed review files", and `docs.spec` asserted that the promoted path existed; both were green only on a clone where the specs had been copied into `tests/acceptance/`.

**How to apply:** run `./zn check <id>` in prep with the specs left in `acceptance/` and none promoted, and run any line about "this branch's files" in a fixture that has committed a review and a refute; list the run in the Unknowns.
