---
title: Members' check files are an interface
when: design
tags: [raft, interfaces, check-sh]
check: Does any member's spec read tracker files (finished check.sh files, inputs.tsv, watch files, item folders), and if so was its rule run on the other members' own files as they will sit after `./zn done`, with a raft check that holds the result?
---
Disjoint Touched lists are not the whole interface between members. A spec that scans the tracker reads what the raft itself adds to it: each member's `check.sh` moves to `done/` with the raft, and a member's table or list file may be read by another member's spec.

**Why:** R0133 (2026-11-17) grouped four chores that each fix one promoted spec, and its Whole-raft design said "no interface between members". Coherence review 001 F1 ran c0374's rule (`c0120/finished` reads every finished `check.sh`) on the members' own `check.sh` files: c0388's AC3 named `z-nile/engine/store.luau` from the home `z-nile`, so the day the raft landed the spec c0374 turns green would have gone red again. F3: two members made the same kind of change and only one updated `tests/inputs.tsv`.

**How to apply:** For each member whose spec walks tracker folders or shared list files, run that rule on every other member's files in the place `done` gives them, in rafting. Hold it with an RCn check that finds the members with `./zn members`. A member that fails goes back to z-design (`./zn unfold`); never widen another member's rule to let it pass. Name in the Whole-raft design any shared list (inputs.tsv, a watch file) that members change differently.
