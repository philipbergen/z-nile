---
title: Members' sequestered specs run on all members' prototype patches together
when: design
tags: [raft, specs, scans, prototype]
from: R0070 design review 001 F2, F7
check: Has each member's whole acceptance set (repository-wide scans and allow-lists above all) run on a tree with every member's prototype patch applied, and is each red case a declared Override or a named interface?
---
"Independent in code" is a claim about modules, but a scan reads every file.

**Why:** R0070 design review 001 F2: c0194's `callers.spec` scan flagged the `mktemp` in c0189's code once both prototypes were applied; neither design nor the raft listed it.

**How to apply:** apply the members' `prototype.patch` files to a scratch clone (under `.cache/.tmp` once c0194 lands), run every member's acceptance set, and write the interfaces the reds name.
