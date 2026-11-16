---
title: A guard's decision is made from what it guards, not inside the branch of an optional feature
when: both
tags: [guards, fail-closed, optional-features]
check: When an optional feature (a results db, a cache) can be switched off by a failure, does each guard decision (may this run record, write the marker, refuse) still run when it is off, and is there a case that turns the feature off and trips the guard?
---
Putting a guard inside `if feature is available then` makes the guard vanish with the feature.

**Why:** R0081 code review 002 F3: the weak-jail check and its no-record marker sat under `db ~= nil`; a failed rows read set `db` to nil, so a weak-jail run wrote no marker and `gate-record` then recorded the gate.

**How to apply:** decide the verdict from the run alone (its jail, its exit), then write rows only when the db is open. Pin it with a case that fails the feature and trips the guard.
