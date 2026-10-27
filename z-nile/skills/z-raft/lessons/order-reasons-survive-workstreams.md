---
title: An Order's stated reason survives ./zn workstreams
when: design
tags: [raft, order, workstreams]
from: R0061 design review 001 (the reviewer's candidate lesson)
check: Does `./zn workstreams <R-id>` run the members in the order the Order section relies on, or does a stated reason ("X runs last so it sees Y's edits") vanish when the plan says `parallel: yes`?
---
Members that share no file and no depends_on run as parallel workstreams in one wave, so an order written into the raft document is not what execution does.

**Why:** R0061 design review 001 F1: the Order said c0137 runs last so its checks read c0135's skill edits, but `./zn workstreams R0061` put all three in wave 1.

**How to apply:** run `./zn workstreams` before writing the Order. A coupling that needs one member's check to see another's change is proved by every member's check after the last merge (zz-execute Phase 2B step 6) and RC0; say that. An order execution must follow goes in `depends_on`.
