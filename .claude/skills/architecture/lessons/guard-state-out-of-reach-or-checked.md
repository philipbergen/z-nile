---
title: A guard's own state is out of reach of what it guards, or checked against a copy that is
when: design
tags: [security, detection, state]
check: Can the guarded process delete or rewrite the guard's record (a file, a config entry, a remote URL), who else legitimately writes that record, and what does the guard do when it is missing or changed: trust it, stop, or re-check what it guards from its own copy?
---
A watermark file the step can delete, read back after the step, turns one `rm` into a quiet tripwire; a remote URL read from the shared git configuration lets the step point every later check at a frozen copy. Hold the guard's state in the guard's own memory for the run and re-check what it guards from that copy; when other legitimate processes write the record (another run, the user's command), never fail on the record merely differing (c0117 design review 004 F1: two dispatchers tripped each other), and let it only move forward under a lock. Never trust a missing record (only the user's act writes the first one), pin the URL at the start and compare the configuration after each step. Where the same OS user can still rewrite it between runs, say so as a known limit.

**Why:** c0117 design review 003 F2 and F3: a step deleted the watermark and pushed code past the wrapper; another repointed `remote.origin.url` at a frozen copy; both tripwires stayed quiet.

**How to apply:** the in-memory copy, a mirror the next run compares, a pinned URL, and spec cases that delete, rewrite and set back the record and repoint origin.
