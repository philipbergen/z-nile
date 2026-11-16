---
title: The Order section names each member once and no other item id
when: design
tags: [raft, order, layers, stack]
check: Run over the `## Order & dependencies` section as `layergit.raftSection` cuts it (up to the next `## `): is every item id in it a member, and is each named only once?
---
Since layers (#296), `layergit.orderedMembers` passes the whole Order section to `stack.order`. That function reads every `[fdc]NNNN` in it, in order, and fails on a non-member or a repeat. `./zn start`, `finish`, `stack`, `commit` and `done` then refuse the raft. `./zn status <R> prepared` and `ready` do not run it, so a broken Order is found only when the first layer starts.

**Why:** R0077 design review 001 F1. R0077's Order named c0141, c0194 and c0189 (cross-raft waits) and pasted a `./zn workstreams` block that named its members a second time. R0072's Order named c0191. A scan at d0298's rafting (2026-11-12) found the same defect in most rafts on main, five active ones among them.

**How to apply:** in the Order, name members only, each once, in stacking order. Raft ids (`R0062`) are not item ids and may stay. Put item-level cross-raft waits in a `## Cross-raft waits` section, and quote only the last line of `./zn workstreams` (`parallel: …`), never its per-member lines.

**Note** (R0100 design review 002 F1): `./zn workstreams` does not read `## Order & dependencies`, so an RC that pins workstreams proves nothing about the order `start` reads. A verbatim user ruling that names a member, added to the Order section in a later edit, made `stack.order` refuse ("c0277 is listed twice") while RC1 stayed green. After any edit inside that section run `./zn stack <R-id>` and read it; RC1 now runs it. Ask: was `./zn stack <R-id>` run after the last edit to the Order section?

**Note** (R0090 rafting #321, 2026-11-12; c0309): a layer branch such as `R0090/1/c0261` names its member a second time. R0090's Order held both `**c0261**` and `R0090/1/c0261`, and `./zn start R0090` refused with "c0261 is listed twice in R0090's Order" only after the raft was readied. Run `./zn stack <R-id>` on the rafting branch before the rafting pull request is opened, and read its answer. (Non-member ids in existing rafts' Orders are a separate matter, d0295.)
