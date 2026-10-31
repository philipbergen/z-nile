---
title: An "any element decides" rule needs the decider first and last in some case
when: design
tags: [mutants, loops, cases]
check: For each any/all rule, is the deciding element placed both first and last (and between) in some case, so a loop that overwrites instead of accumulating goes red?
---
A rule stated as "if any entry is X, then…" is usually a loop with a flag. Cases that always put the X entry last pass a loop that overwrites the flag on each entry (the last one decides), and cases that always put it first pass one that stops early.

**Why:** c0141 design review 003 F1: every mixed Touched case put the `<home>/` entry last, so `fromTop = <this entry is a home>`, overwriting, passed all specs; c0117's own order (root files after `z-nile/…`) would then be misread.

**How to apply:** for each any/all rule, write a case with the decider first, one with it last, and one with it in the middle, and list the overwrite and first-decides mutants in Rules and mutants.
