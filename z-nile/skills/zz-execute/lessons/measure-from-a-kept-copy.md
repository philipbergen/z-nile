---
title: A measurement read from a cache file names its command and keeps a copy of the input
when: build
tags: [verification, measurement, caches]
check: Could anyone rerun this logged figure tomorrow: does the log give the exact command, and is the input it read kept (copied, or its write time noted) rather than a cache the next run overwrites?
---
A Verification-log figure computed from a file the tooling rewrites (a duration record, a cache, a report) can't be checked once the next run overwrites it, and without the command it can't be recomputed even while the file exists.

**Why:** R0055 code review 001 F2: JC1's 730.0 s / 565.6 s were computed from `z-nile/.cache/spec-durations.tsv`, which R0055's own RC0 run rewrote an hour later; the reviewer's recomputation gave 442.2 s / 311.2 s, and the log had no command to say how either was made.

**How to apply:** log the command (or the few lines of code) with each figure, note when its input was written, and copy the input into the item's folder when the figure is an acceptance measurement.
