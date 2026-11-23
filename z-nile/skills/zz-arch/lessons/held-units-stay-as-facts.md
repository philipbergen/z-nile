---
title: Never delete facts to hide a unit
when: both
tags: [worker, claims, facts, walk]
check: When a unit must be kept from a worker (held by another, lost, blocked), is it kept in the facts with a mark the decision rule reads, instead of being filtered out before the rule runs?
---
A rule that decides order needs to know a held unit exists. Removing it makes everything that depended on it look free.

**Why:** f0420 step 4b (2026-11-21, code review): held rafts were filtered out of the facts before the walk; a second worker was then handed a ticket whose dependency, held by the first worker, was no longer visible as unfinished.

**How to apply:** pass claims to the pure rule as input. Spec: a held unit with a dependent, and assert the dependent waits, naming the holder.
