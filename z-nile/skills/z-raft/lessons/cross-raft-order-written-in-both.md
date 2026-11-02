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
