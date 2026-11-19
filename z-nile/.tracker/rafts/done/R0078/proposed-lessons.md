# Proposed lessons (R0078, raft coherence review 001)
The rafting lead was a subagent and does not write lesson files; texts for the lead to write under `z-nile/skills/z-raft/lessons/`. F2 sharpens the existing `z-raft/order-reasons-survive-workstreams` (the stated reason for an order must be the real blocker, and an order the engine does not enforce is said so).

## z-raft/cross-raft-order-written-in-both
```
---
title: A cross-raft order is written in both rafts, and never inside lines a member's check pins
when: design
tags: [raft, order, pins]
from: R0078 design review 001 F1
check: For each "X before Y", does Y's raft document say it, and would writing it there touch a pinned file or a line within three of a patch hunk?
---
An order recorded in one raft is read by the lead of that raft only, and a note added to a document a member's check pins (a patch that must apply without fuzz) turns that check red.

**Why:** R0078 design review 001 F1: the "R0078 before R0070" order was written only in R0078; a dated note placed directly under a Design heading in c0075.md fails c0173's AC3.

**How to apply:** write the order in both raft documents with the merge (not ready) as the trigger, and give a placement rule for any note that lands in a pinned document.
```

## z-raft/rc-pins-the-claims-it-makes
```
---
title: A raft's Order or Risks claim of "no code changes" or "only X changes" is pinned by an RC line
when: design
tags: [raft, rc, claims]
from: R0078 design review 001 F3, R0070 design review 001 F4
check: Does each factual claim the raft makes about what execution changes or proves have an RCn line that fails when the claim is false, and does that RC print something other than "nothing to judge" on the raft's own branch?
---
A claim no check backs is drift waiting to happen.

**Why:** R0078 F3: "no code is written" was backed by no check; R0070 F4: an RC whose empty state passed proved nothing.

**How to apply:** add an RC that diffs against the merge base for "only X changes"; run each RC on the raft's own branch and read what it prints.
```
