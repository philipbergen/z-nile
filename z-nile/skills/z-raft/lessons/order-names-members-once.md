---
title: The Order section names each member once and no other item id
when: design
tags: [raft, order, layers, stack]
check: Run over the `## Order & dependencies` section as `layergit.raftSection` cuts it (up to the next `## `): is every item id in it a member, and is each named only once?
---
Since layers (#296), `layergit.orderedMembers` passes the whole Order section to `stack.order`. That function reads every `[fdc]NNNN` in it, in order, and fails on a non-member or a repeat. `./zn start`, `finish`, `stack`, `commit` and `done` then refuse the raft. `./zn status <R> prepared` and `ready` do not run it, so a broken Order is found only when the first layer starts.

**Why:** R0077 design review 001 F1. R0077's Order named c0141, c0194 and c0189 (cross-raft waits) and pasted a `./zn workstreams` block that named its members a second time. R0072's Order named c0191. A scan at d0298's rafting (2026-11-12) found the same defect in most rafts on main, five active ones among them.

**How to apply:** in the Order, name members only, each once, in stacking order. Raft ids (`R0062`) are not item ids and may stay. Put item-level cross-raft waits in a `## Cross-raft waits` section, and quote only the last line of `./zn workstreams` (`parallel: …`), never its per-member lines.
