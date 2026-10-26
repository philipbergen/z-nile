---
title: Rules table ids are the mutation runner's ids
when: design
tags: [mutants, records, review]
check: Does every Rules and mutants row's id run that row's mutant when passed to the mutation runner (`mutants.py <id>`), and does every runner entry have a row?
---
A reviewer checks a `run` row by rerunning its mutant. When the table numbers rows one way and the runner names mutants another, the rerun picks the wrong mutant (or none), and a survivor can hide behind a row that looks killed.

**Why:** f0126 design review 003 F4: the table's G1 to G3 and R2a to R2i named different mutants in `experiments/mutants.py` (whose G1 to G9 were round 2's), and the first-draft count was off by one.

**How to apply:** give each runner entry the row's id as its prefix, keep one row per id (a row with two mutants lists both ids), and count the rows from the runner's output when writing the mutation experiment.
