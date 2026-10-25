---
title: An override of a finished item's check.sh lands before the raft is readied
when: design
tags: [overrides, sequestration, finished, process]
check: Does any Overrides bullet name a `done/…/check.sh`? Is that edit in this item's prep PR (or a tracker PR) on main before z-ready, rather than left for the execution branch?
---
A finished item's `check.sh` is sequestered like any other: during execution it changes only for a layout move the user decided on. An override that must drop or narrow a line in another item's finished `check.sh` therefore belongs in the overriding item's prep PR, or a tracker PR, so it is on main before the raft is readied, and the execution branch's sequestration diff stays R100.

**Why:** R0050 code review 001 F1 (high): c0116's override of c0115's finished `check.sh` (dropping the clause that z-raft must not exist) was made in the execution branch. Its content was right, but zz-test allows that only for a user-decided move, and c0115's own `rewrite-finished --check` turned red on the branch. c0116's prep PR landed after c0115 and could have carried it.

**How to apply:** at prep, list every `done/…/check.sh` an Overrides bullet changes, make the edit in the prep commit, and check the execution branch's sequestration diff lists none of them.
