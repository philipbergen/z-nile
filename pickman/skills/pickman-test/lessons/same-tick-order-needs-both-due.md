---
title: A tick's order is pinned by a case where both events are due on the same tick
when: design
tags: [specs, ticks, order, simulation]
check: For each pair of events the Design orders within one tick (a clear before a hit, a hit before the march), is there a case whose fixture makes both due on that very tick, a control case that shows the later one does happen when the earlier is absent, and a mutant that swaps the two steps?
---
A step function that runs its parts in a fixed order makes that order a rule, but a case where only one of the two events can happen that tick passes for any order. Swapping two steps then ships a softlock or a wrong reason.

**Why:** f0216 design review 001 F1: the Design said "a shot that clears the wave ends the tick before any alien shot can hit" and "a hit on the cannon ends the tick before the formation moves", but the clear case's bomb could not reach the cannon and the hit case's formation could not move that tick. Swapping the clear and the hit left a field with no aliens and no clear, and all 59 cases passed.

**How to apply:** for each ordered pair, set both due by hand (a shot one tick from its target, a bomb one tick from the cannon, the formation's wait one tick from due and its next move an advance), assert the tick's exact event kinds, and run the same fixture without the earlier event as a control; add the swapped-steps mutant and the "does not end the tick" mutant to the Rules table.
