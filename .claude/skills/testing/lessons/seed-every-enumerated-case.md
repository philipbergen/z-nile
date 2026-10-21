---
title: Seed every case the code enumerates
when: both
tags: [fixtures, coverage]
check: Does the fixture seed every value of each set the code walks (every state folder, kind, mode or stream), and every combination when it walks two sets at once (kinds × states), so that dropping one turns a spec red?
---
When code iterates a fixed set (the backlog, `active/` and `done/` folders; issues and rafts; stdout and stderr), the spec fixture must hold at least one case of each value. A fixture that covers only some of them lets an implementation silently skip the rest.

**Why:** R0040 design review 1 (F1): `load` walks the backlog, `active/` and `done/`, but the CLI fixture seeded nothing under `active/`. Dropping `active/` still passed, which is exactly where a raft sits while its own checks run.

R0040 design review 2 (F2) found the same gap one level down: after `active/` was added, the fixture still covered only 3 of the 6 kind × state folders, so a reader that skipped `rafts/done` (where every finished raft's ledger lives) passed.

c0120 code review 002 F2: the fence strips ten overrides, and the cases seeded only `GIT_DIR`. A fix that stripped `GIT_DIR` alone before the read passed them; `GIT_COMMON_DIR` at another repository then escaped.

**How to apply:** for each loop over a fixed list in the Design, name the fixture entry that covers each element, and add a Rules row whose mutant drops one element. For nested loops, cover the cross product, not each list once.
