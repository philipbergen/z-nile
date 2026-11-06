---
title: A pin added in a late round runs on the tree with every dependency merged
when: design
tags: [pins, dependencies, prototypes]
check: For each new source pin or stub, does any `depends_on` design quote the line it matches, and has it run on a tree with every dependency merged?
---
A source pin or stub added in a late review round is usually written against the prototype at hand. If a dependency's ready design changes the same line, the pin is red on the tree the executor starts from, in a sequestered file the executor may not edit.

**Why:** f0143 design review 003 F1: round 002 added a camera pin naming `Hop.rise(hopped, shown)` in full, but f0126, which f0143 depends on, makes that call `Hop.rise(hopped, shown, hopTicks)`. The pin had run only on a prototype without f0126.

**How to apply:** pin only the part of a line this issue owns (stop the pattern where another issue may add arguments), and before the round's answer is pushed, run every sequestered spec on one tree with every `depends_on` merged; record the run and what failed there that isn't yours.

c0239 design review 005 F2: docs.spec pinned two Merging sentences that the readied c0194 rewrites, so whichever lands second fails its checks. Pin a sentence only up to the clause the issue owns, name the other item in Existing work, and run the pins with and without its patch applied.
