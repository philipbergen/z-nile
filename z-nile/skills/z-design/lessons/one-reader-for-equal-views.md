---
title: Two views of one history are read by one function
when: design
tags: [reader, board, who]
check: Does each reader the Design names (a CLI, a page) apply the same cut, the same inputs and the same selector, and does the equality case use an item that needs each of them?
---
"A equals B" in an acceptance criterion is a statement about one reader. Two readers that differ in a cut (a compaction), an input (a per-commit value) or a selector agree on the item the spec chose and differ on the next.

**Why:** c0263 design review 007 F1: the board's one-pass reader and `who`'s per-item reader differed for items that needed the compaction cut or the per-commit `raft:` values, while the board case looked at an item that needed neither.

**How to apply:** name the shared function, state the entries one view leaves out and why, and compare both views on one item of each kind.
