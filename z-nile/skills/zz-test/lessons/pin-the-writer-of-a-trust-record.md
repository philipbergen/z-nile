---
title: When a guard believes a record, a spec pins what the real writer writes
when: both
tags: [specs, guards, registry]
check: Is there a case that reads the record (a registry, a lock, a marker file) the real writer made during a real run and asserts its exact content, and a mutant of the writer?
---
Readers tested on a record the spec plants pass with a writer that records too much: the guard's decision lives in two halves, and the half that carries the user's decision is the one nobody pinned.

**Why:** c0123 design review 009 F1: every case of the allow-listed environment planted its own `tests-run.lock/folders`; changing the runner's one line to register the whole `.cache/.tmp` passed seven spec files (86 of 86) and undid the user's "Exclude .cache/.tmp" decision.

**How to apply:** read the live record in a spec (every spec runs under a live run) and assert exactly one line, equal to the canonical run folder, held by a live owner; add an end-to-end case with a lookalike beside it, and mutants of the writer (wider, narrower, an extra line). A record whose owner is gone (a killed run) proves nothing: give the readers the liveness test, and plant a dead pid instead of killing a process.
