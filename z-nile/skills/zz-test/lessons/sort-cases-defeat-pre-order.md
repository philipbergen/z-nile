---
title: A sort case must fail when the sort is deleted
when: both
tags: [specs, ordering]
check: Would this case pass if the sort were deleted, under every hash order of the input? Do its keys sort differently from a parent-first walk of the tree (such as `A`, `A-`, `A/Z`)?
---
A case that pins "sorted by key" over a walk of a tree passes without the sort when the fixture's natural order (parents first, keys in the order Luau happens to iterate them) equals the sorted one. The recorded mutant "reverse order" hides it: the plausible mistake is forgetting the sort.

**Why:** c0246 design review 001 F1: the sort case for `graph.unreadable` passed an implementation that never sorted.

**How to apply:** pick keys where a child's full path sorts after a sibling that a parent-first walk visits last (`A-` between `A` and `A/Z`), and run the mutant "no sort" in the mutation check.
