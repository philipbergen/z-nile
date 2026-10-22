---
title: A new rule says how existing work gets through it
when: design
tags: [process, migration, rollout]
check: When this adds a rule or a check, which existing items (prepared, active, mid-prep, done) fail it on the day it lands, and what does the design say they do?
---
A new requirement is written for the work that comes after it, but it is checked against everything already in flight. Prepared rafts, active ones and preps open on a branch were made under the old rules and fail the new check the moment it lands, unless the design gives them a path (a migration, a harvest-at-confirm, an exemption, or an order).

**Why:** R0040 design review 5 (F1): the new "confirm the harvest" step would have blocked the three rafts already prepared, whose design reviews had no `harvest.md`. The Risks section said nothing would fail until a later gate. The user chose to have each old raft's executor harvest its own rounds at the confirm step.

c0120 design review 005 F6: when c0120's redesign moved z-nile's home from the root to `z-nile/`, c0115's prep (approved against the first revision) still ran its `check.sh` from the root. A change to a decision other preps were designed against is a new rule for them: name each one and its path (here: re-prepped before c0120 is readied, and a Phase 1 check that every unfinished `check.sh` resolves from its home).

**How to apply:** list the items on `main` and on open branches that the new rule applies to, run the new check against them in prep, and write their path into the design. Where the path is a cost or an ordering, put it to the user.

A rewrite rule written from the cases a sample showed misses the forms the sample didn't: c0115's rule 3 matched only `s=../.claude/skills`, and c0040's `R="$(git … --show-toplevel)/.claude/skills"` stayed broken while the exact check was green (design review 010 F2). Pair the rules with an independent scan that fails on any old form left, and run the before-and-after comparison over every file that names the old thing, not only the ones the rules edited.
