---
title: A lock over who may change a thing detects the change, not only a live claim
when: design
tags: [concurrency, claims, state]
check: If another terminal claims, changes and lands the item entirely inside this claim's window, what notices?
---
A claim check sees only claims that are still open. A change that another terminal claims, makes and lands between two of your checks leaves no claim behind, so a lock that asks "is anyone holding it now?" lets the change through, and your later step works from what it read before the change.

**Why:** c0116 design review 002 F1: the rafting checked for a live `preparing` claim on each member. A complete z-design cycle (claim, redesign, carried prepare, land) inside the rafting window left the member `prepared` again, so the carried move took it "as it is", and `ready` handed out a raft whose coherence review read the old design. This was the third hole in the raft-only stamp.

**How to apply:** record what the claim read (a hash of the item, its stamp) at the moment it reads it, and compare at every later step that relies on it (the carried move, `ready`). Refuse on a difference, and name both values. Then try the both-orders cases: a full change landing before the next step, and one landing after it.
