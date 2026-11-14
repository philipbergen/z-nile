---
title: A flow that keys its state by a slot many runs reuse is proven with two runs in a row
when: design
tags: [dispatch, state, slots]
check: Does any run state live in a slot that every later run of the same kind reuses (the dispatcher's `new` folder), and does a spec run the flow twice in one fixture, including after a stop and after a failure, so that a slot the first run left "running", full or stale blocks the second?
---
A design that says "the next one starts clean" is a claim about the slot the first run leaves behind, and one run never shows it.

**Why:** c0256 design review 001 F3: the first design moved a capture's state to its issue and said a later `dispatch new` starts clean. The slot `new` stayed `running` after every capture (a c0117 bug), so the second capture was refused as "lost"; the recovery (`retry new`) became a dead end once the design refused a retry without words; and a failed capture's stop named no id.

**How to apply:** list every slot a run reuses (a folder named for a kind, not an item). For each, say what the slot holds when a run ends ok, stops for the user, fails and dies, and run the flow twice in one spec fixture for each of those. A migration case covers a slot an earlier version left in a state the new code never writes.
