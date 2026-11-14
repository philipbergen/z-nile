---
title: Pin each branch of a diff function
when: design
tags: [mutants, specs, guards]
check: For a guard that compares two texts line by line, does some case reach each of its branches (a changed line, an added line in a wrong place, a missing middle line, and a text that ends early), so that a mutant in any one branch fails a case?
---
A line-by-line comparison has several exits: a mismatch in the middle, an addition, and the tail when one text runs out first. A deletion in the middle of a document is caught by the mismatch branch, so a case that removes a middle line never reaches the tail branch, and a mutant there survives.

**Why:** c0250's prototype (prep, 2026-11-13): the mutant "a removed or changed last line is accepted" survived the publish-rule spec until a case gave a document that lost its last lines.

**How to apply:** list the comparison's branches and give each one a case: a document that ends early, one with an extra tail, one with a changed middle line, and one with an added line outside the allowed place.
