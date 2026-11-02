# Proposed lessons from c0112's design reviews (for the lead of this prep to write; a subagent writes no lesson file)

Each block is a complete lesson file for `<skills folder>/<skill>/lessons/<slug>.md`. Their ids are the ones `harvest.md` names.

## z-design/checks-run-as-done-runs-them
```
---
title: A check is proven as `done` runs it, after the raft's own steps
when: design
tags: [check-sh, acceptance, promotion]
check: Was every check.sh line and acceptance spec run in the layout `done` sees (the specs still in the issue's acceptance/ folder, the raft's own code review and refute already committed), and does each still pass there?
---
A criterion proven in a layout that never occurs during execution passes in prep and fails at `done`. `done` runs `check.sh` before it promotes the specs and after the raft's own review files are committed.

**Why:** c0112 design review 001 (F1, F2): AC6 counted the raft's own `review-NNN.md` and `refute-NNN.md` as "changed review files", and `docs.spec` asserted that the promoted path existed; both were green only on a clone where the specs had been copied into `tests/acceptance/`.

**How to apply:** run `./zn check <id>` in prep with the specs left in `acceptance/` and none promoted, and run any line about "this branch's files" in a fixture that has committed a review and a refute; list the run in the Unknowns.
```

## zz-test/nothing-lost-compares-sets
```
---
title: A "nothing lost" check compares sets keyed by identity, never counts
when: both
tags: [coverage, migration, sets]
check: Does this check still go red when one member is lost and another is added in the same change, and does it compare every member exactly, with the allowances a rule over the input rather than a list of today's instances?
---
A check that compares counts, or a running count, cannot see a loss that the same change pays back with an addition, and a change that adds members (a backfill) always does.

**Why:** c0112 design review 001 F3 and review 002 F2: AC3 compared source counts (one source dropped while another was added to the same lesson passed), then a running count for notes (a dropped first note of two passed); design review 003 F4: its list of five reworded notes was frozen at prep while main kept adding such notes; design review 004 F1 and 005 F1: the "both merge parents" check was written over lesson ids and went red for c0181's consolidation, which keeps every source, and its first fix required exactly one holder, red for a merge whose sources sit in two lessons.

**How to apply:** key each member by its identity, compare the sets, allow a rewording only by a function of the old text, state the invariant over contents (sources), not over ids, when a sibling change merges or renames ids (c0181's lesson-merge deletes an id and keeps its sources), and add a case for "one lost, one added" and one where the invariant holds and the check's extra condition alone would fail it.
```

## z-design/judged-criteria-pass-per-stratum
```
---
title: A Judged criterion that samples passes per stratum, not in aggregate
when: design
tags: [judged, acceptance, sampling]
check: Does the rubric give each stratum of the sample its own threshold, so that a whole stratum (the one most likely to be gamed) cannot fail inside a passing total?
---
An aggregate percentage over a mixed sample lets one stratum be poor while the total passes, and the Checked criteria may pass on placeholders, so the Judged one is the only guard.

**Why:** c0112 design review 001 F10: JC1's 90% rule let three bad one-offs pass in a sample of 32.

**How to apply:** list the strata, give each a small-sample threshold (for example 7 of 8), say that a failing stratum is redone and re-sampled, and add a stratum for any outcome the Checked criteria cannot judge.
```

## z-design/run-a-rule-over-the-whole-input
```
---
title: A selection rule is run over the whole input and its answers counted
when: design
tags: [experiments, selection, measurement]
check: Over today's full input, how many items does this rule select or hold, and why each, before the design relies on it?
---
A rule tried on three examples can select almost everything, or almost nothing, over the real input.

**Why:** c0112 design review 002 F5: the "held" rule built on `./zn busy` was tried on three folders; over the tree it held nearly every item (it names every active raft for any path, and stale prototype branches "change" about 128 `done/` folders).

**How to apply:** run the rule over the whole set in prep, record the count and the reason for each selection in the Unknowns, and fix the rule if the count is not what the design needs.
```
