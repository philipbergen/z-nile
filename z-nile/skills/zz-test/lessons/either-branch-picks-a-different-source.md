---
title: "A when X, else B" needs a case where X is false and A and B differ
when: design
tags: [cases, mutants, branches]
check: For each "A when X, else B" in the design, is there a case with X false where A and B differ, and one with X true where they differ?
---
A rule that picks between two sources passes every case in which the two agree, whichever one the code reads. So "always A" and "always B" both survive until a case makes them disagree in each branch.

**Why:** c0152 design review 005 F1: the live-item rule reads the PR's copy when the PR changed the folder, else main's. Every case had the PR change the folder, or used an item both sides held, so a mutant always reading the PR's copy answered ok over a main whose own commits orphaned a spend row.

**How to apply:** for each branch, write a case where the two sources differ (here: main moves an item the PR doesn't touch, then lands a row at its old folder), and list "always A" and "always B" as mutants.
