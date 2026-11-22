---
title: Every guess that states a rule gets a Rules and mutants row
when: design
tags: [guesses, mutants, specs]
check: Does each guess that states a rule have its own row in Rules and mutants, naming the test that fails when the guess is reverted?
from: f0437 design review 001 F3 (2026-11-21)
---
A guess the design records but never pins can be reverted without a spec noticing.

**Why:** f0437 design review 001 F3 (2026-11-21): guesses G2 and G7 had no row, and six mutants survived to review.

**How to apply:** walk the guesses list; for each rule, add a row, a mutant that reverts it, and the case that kills it.
