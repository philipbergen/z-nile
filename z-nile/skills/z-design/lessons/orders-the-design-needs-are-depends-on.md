---
title: An order the design relies on is a depends_on edge, not prose
when: design
tags: [coordination, dependencies, ready]
check: For every "X waits for Y" or "X lands just before Y" this design relies on (a short window, or a residue accepted only because it is brief), is Y in X's `depends_on` or checked in X's step 0, since `ready` and z-work read nothing else? And are Y's chain and the absence of a cycle named?
---
`./zn ready` checks only that every `depends_on` outside the raft is done, and z-work takes the next raft `ready` would accept. Neither stops for prose in a raft's Order & dependencies or for a note to z-raft, so an order written only in words is not kept.

**Why:** c0392 design review 001 F2: c0392 chose to land just before f0209, so that an accepted residue would last only one raft. It wrote that order as a sentence for z-raft, while its `depends_on` held only c0210. `ready` would then have taken c0392 as soon as c0210 was done, which is the very option the design rejected.

**How to apply:** put the edge in `depends_on`, check it in step 0, and name the chain it brings (lesson z-design/depends-on-inherits-the-dependency-raft). The user's option to drop the edge becomes the Guess's question.
