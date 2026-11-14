---
title: A landing moves every raft's base in a shared fixture
when: both
tags: [fixtures, stacks, restack, scenarios]
check: In a fixture that holds several rafts behind one origin, is each raft's sequence of cases contiguous (or restacked first), so that another raft's landing moving `origin/main` does not leave this raft's lowest layer unstacked between its cases?
---
Every landing moves `origin/main`. In a fixture with several rafts, another raft's landing leaves this raft's lowest unlanded layer behind `main` (`claimed` in `./zn stack`, refused by `finish`, `done` and `trace` until `./zn restack`), so a case that passed alone fails when the cases are interleaved.

**Why:** c0248's prototype: layers-land runs eight rafts in one fixture, and a case for one raft failed with "is not based on main" after a case for another raft landed in between.

**How to apply:** keep each raft's cases in a block, or restack at the start of each case that uses a raft another case may have moved; name in the spec's header which raft each case owns. Related: [[scenario-specs-follow-the-decided-order]].
