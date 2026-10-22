---
title: A new rule says how existing work gets through it
when: design
tags: [process, migration, rollout]
check: When this adds a rule, a check or a new data structure, which existing items (prepared, active, mid-prep, done) or stored data fail it on the day it lands, what does the design say they do, and, for a one-time migration, which writers (older builds, old servers, a rollback) still produce the old shape after it ran, and does the new structure pick their data up?
---
A new requirement is written for the work that comes after it, but it is checked against everything already in flight. Prepared rafts, active ones and preps open on a branch were made under the old rules and fail the new check the moment it lands, unless the design gives them a path (a migration, a harvest-at-confirm, an exemption, or an order).

**Why:** R0040 design review 5 (F1): the new "confirm the harvest" step would have blocked the three rafts already prepared, whose design reviews had no `harvest.md`. The Risks section said nothing would fail until a later gate. The user chose to have each old raft's executor harvest its own rounds at the confirm step.

**How to apply:** list the items on `main` and on open branches that the new rule applies to, run the new check against them in prep, and write their path into the design. Where the path is a cost or an ordering, put it to the user.

R0044 design review 1 (F1): the new all-time list of runs was seeded once from the per-player bests, when no list existed. Beta publishes the last ready PR and leaves running servers alone, so builds without the list kept writing per-player bests after the seed, and those runs never reached the list. The fix merged the per-player bests on every write. A one-time migration is only safe when nothing keeps writing the old shape after it.
