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

**Note** (R0100 rafting, 2026-11-13): merging the five heartbeat prototypes was textually clean in `main.luau` but wrong: c0276's prototype, cut from an older c0265, forward-declared `local hb = {} :: {…}` before `buildBoard`, and the merged file then held two `local hb` declarations; the later one shadowed the first, so every function defined on the first table (the beat, the autobeat, the beater) was nil to the code below it, and each caller's `pcall` swallowed the error ("a beat never fails the command"). Only the real-time proofs of c0265, c0275 and c0277 went red (the fast specs passed). Merge the prototypes in `depends_on` order, then count the top-level declarations of every table or local more than one member declares (`grep -c '^local hb'`), and run the real-time proofs on the merge one at a time (five checks at once also fail them, by load). Ask: does the merged file declare each shared table once?
