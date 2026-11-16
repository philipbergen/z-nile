---
title: A store stub must catch a blind read-then-write
when: both
tags: [stubs, datastore, atomicity]
check: Does the stub change the stored value between the adapter's read and its transform, and call the transform more than once, so only a decision taken inside the transform's last call passes?
---
A `DataStore:UpdateAsync` stub that runs the transform once, from one thread, on the value it holds cannot tell an atomic update from a `GetAsync` followed by a blind write, nor a decision taken from the transform's first call from one taken from its last. Real `UpdateAsync` may call the transform again on a newer value written by another server.

**Why:** f0145 design review 001 F5: receipt idempotency and the one free start were claimed atomic, but a read-then-write grant and a first-call answer passed every case.

**How to apply:** give the stub a race hook that writes a competing value just before the transform and a mode that calls the transform first on the stale value, then again; add cases where another server granted the same receipt or took the free start, and run the blind-write and first-answer mutants.
