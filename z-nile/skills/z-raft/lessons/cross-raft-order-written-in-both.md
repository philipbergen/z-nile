---
title: A cross-raft order is written in both rafts, and never inside lines a member's check pins
when: design
tags: [raft, order, pins]
from: R0078 design review 001 F1
check: For each order or pinned shape another item must honour, does that item's raft say it (or, when it has no raft, this raft and its pull request, outside that item's grouped record), and would writing it there touch a pinned file or a line within three of a patch hunk?
---
An order recorded in one raft is read by the lead of that raft only, and a note added to a document a member's check pins (a patch that must apply without fuzz) turns that check red.

**Why:** R0078 design review 001 F1: the "R0078 before R0070" order was written only in R0078; a dated note placed directly under a Design heading in c0075.md fails c0173's AC3.

**How to apply:** write the order in both raft documents with the merge (not ready) as the trigger, and give a placement rule for any note that lands in a pinned document.

**Note** (R0110 design review 001 F3): f0145 has no raft document, and its grouped record is another prep's. The note that a landed f0201 pins its record shape, store names and attributes lives in this raft and in the rafting pull request, not in f0145.md.
