---
title: An Order's stated reason survives ./zn workstreams
when: design
tags: [raft, order, workstreams]
from: R0061 design review 001 (the reviewer's candidate lesson)
check: When `./zn workstreams` prints a different order from the Order section, does the raft say the layers follow that section, and does that section make each member's "if it exists" step fire?
---
Members that share no file and no depends_on run as parallel workstreams in one wave, so an order written into the raft document is not what execution does.

**Why:** R0061 design review 001 F1: the Order said c0137 runs last so its checks read c0135's skill edits, but `./zn workstreams R0061` put all three in wave 1.

**How to apply:** run `./zn workstreams` before writing the Order. A coupling that needs one member's check to see another's change is proved by every member's check after the last merge (zz-execute Phase 2B step 6) and RC0; say that. An order the layers run is the Order section, which `./zn stack` reads. It is a member `depends_on` only when that member's design has one.

**Note** (R0110 design review 001 F1): `./zn workstreams` orders by overlap and id, so it printed f0199 in wave 1 while the interface needs f0201's `## Features` first. zz-execute Phase 2 runs the Order section. Saying an interface order must be a `depends_on` kept the order that skipped the conditional edit. After the Order edit, run `./zn stack`.
