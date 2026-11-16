---
title: A raft's Order & dependencies section names only its members
when: design
tags: [raft, order, start]
check: Does the raft's Order & dependencies section hold any item id that is not one of the raft's members?
---
The engine reads every item id in a raft's Order & dependencies section as a member, in that order. An id of another item there, even in a sentence that says it is not in the raft, makes `./zn start` refuse the readied raft (`<id> is in <R-id>'s Order and is not a member`).

**Why:** R0113 and R0114 (2026-11-15): each raft of one named the other items that touch the same files in its Order section. R0113 was readied, `./zn start` refused, and the raft had to be stopped, fixed by a second rafting pull request and readied again.

**How to apply:** put outside items (who else edits these files, what lands first) under Risks & rollback or in the Theme. Before `./zn status <R-id> prepared`, read the Order section for any id that is not in `issues:`.
