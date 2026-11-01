---
title: A "nothing lost" check compares sets keyed by identity, never counts
when: both
tags: [coverage, migration, sets]
check: Does this check still go red when one member is lost and another is added in the same change, and does it compare every member exactly, with the allowances a rule over the input rather than a list of today's instances?
---
A check that compares counts, or a running count, cannot see a loss that the same change pays back with an addition, and a change that adds members (a backfill) always does.

**Why:** c0112 design review 001 F3 and review 002 F2: AC3 compared source counts (one source dropped while another was added to the same lesson passed), then a running count for notes (a dropped first note of two passed); design review 003 F4: its list of five reworded notes was frozen at prep while main kept adding such notes; design review 004 F1 and 005 F1: the "both merge parents" check was written over lesson ids and went red for c0181's consolidation, which keeps every source, and its first fix required exactly one holder, red for a merge whose sources sit in two lessons.

**How to apply:** key each member by its identity, compare the sets, allow a rewording only by a function of the old text, state the invariant over contents (sources), not over ids, when a sibling change merges or renames ids (c0181's lesson-merge deletes an id and keeps its sources), and add a case for "one lost, one added" and one where the invariant holds and the check's extra condition alone would fail it.
