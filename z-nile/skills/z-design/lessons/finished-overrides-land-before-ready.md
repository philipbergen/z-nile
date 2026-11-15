---
title: An override of a finished item's check.sh lands before the raft is readied
when: design
tags: [overrides, sequestration, finished, process]
check: Does any Overrides bullet or Change name another item's sequestered file (a `done/…/check.sh`, or an unfinished item's `check.sh` or `acceptance/` spec)? Is that edit in this item's prep PR (or a tracker PR) on main before z-ready, or else made by the other item's own prep, or after it is done on its promoted copy, rather than left for the execution branch? And which of the other item's records hash the edited file (its `approval.md` contract, its raft's grouped record), and who redoes each?
---
A finished item's `check.sh` is sequestered like any other: during execution it changes only for a layout move the user decided on. An override that must drop or narrow a line in another item's finished `check.sh` therefore belongs in the overriding item's prep PR, or a tracker PR, so it is on main before the raft is readied, and the execution branch's sequestration diff stays R100.

**Why:** R0050 code review 001 F1 (high): c0116's override of c0115's finished `check.sh` (dropping the clause that z-raft must not exist) was made in the execution branch. Its content was right, but zz-test allows that only for a user-decided move, and c0115's own `rewrite-finished --check` turned red on the branch. c0116's prep PR landed after c0115 and could have carried it.

**How to apply:** at prep, list every `done/…/check.sh` an Overrides bullet changes, make the edit in the prep commit, and check the execution branch's sequestration diff lists none of them.

**Also:** c0288 design review 001 F1 and F3 (high): c0288's raft was to change an unfinished item's (c0260's) sequestered specs. Phase 3 step 4's sequestration diff is repository-wide, so it would have failed. The edit would also have voided c0260's approval (it hashes the specs) and the grouped record of the raft c0260 was rejoining. c0260 had already been sent back to z-design. The fix: the limits go to c0260's redesign, and c0288 waits for c0260 to be done (`depends_on`). It changes only the promoted copies, and only if the redesign missed one.
