---
title: A stacked layer reads what has landed from origin/main, not from its own tree
when: both
tags: [stack, layers, state, origin]
check: Does any rule that asks whether a lower layer, issue or raft has landed (moved to done/, merged) read that fact from `origin/main`, or does it read the layer's own tree, which was cut before the lower layers landed and still shows them in `active/`?
---
A layer's tree is a snapshot from when the layer was cut. Lower layers that land later (a shorter bind below a blocked layer) are in `done/` on `origin/main` but still in `active/` in every layer above them, so a rule that reads its own tree sees them as unlanded and recounts or reopens them.

**Why:** c0248 prep (2026-11-12): the prototype of `./zn done --through` first read "landed" from the worker's layer tree and recounted the landed layers at the second bind; reading the issue's folder on `origin/main` fixed it.

**How to apply:** take every "has it landed" answer from `origin/main` (or the current tree only when it is main), and say so in the Design.
