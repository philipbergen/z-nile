---
title: A cross-raft wait is followed to the layer it stops and to the other raft's own waits
when: design
tags: [raft, order, cross-raft, layers]
check: Which layer's finish runs the red spec the other raft repairs, and is every wait of that other raft `prepared` or better today (`./zn find`)?
---
"Must be done before this raft is done" is wrong when a member's own check runs the red spec: that layer cannot finish, and the layers above it cannot start. The other raft may itself wait on items nobody has designed.

**Why:** R0099 design review 001 F3: c0282's AC7 runs a spec that is red on main, R0096 repairs it, and R0096 waits for three chores still `new` with no raft; the first text said only that the last layer could not pass `done`.

**How to apply:** name the layer the wait stops, write the other raft's chain from `./zn find` at rafting time, and consider ordering the waiting layer last when no `depends_on` forbids it.
