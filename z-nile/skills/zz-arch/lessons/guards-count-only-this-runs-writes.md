---
title: A guard over shared state counts only what this run wrote, recorded when it wrote it
when: design
tags: [guard, shared-state, concurrency]
check: For each guard that asks "what changed since X" over state other sessions write too (origin's issues, main's commits, a shared folder), can another writer make its condition true, and what does the user lose when it does?
---
A guard that compares a snapshot with the shared state refuses whenever anyone else changed it.

**Why:** c0256 design review 003 F1: `retry new` refused every waiting capture once another session had landed an issue ("c0020 was made since this capture began"), though the capture only waited on a question; in this repository sessions land captures every few minutes, so the refusal was the normal case and its only way on dropped the capture.

**How to apply:** count only the writes this run recorded when it made them, and record an action that cannot be recorded after it happens (a push) as an intent just before it, verified against the remote afterwards (c0256 review 004 F2: the broker holds both ends of every push before it pushes); only when no record is possible, run the guard where it protects (not while the user is the one being waited on), name the candidates in the refusal and let the user choose.

**Note (c0256 review 005 F1):** a guard that reads a remote has three answers: found, none, or cannot tell. A failed fetch, an ancestry check that errors or a failed diff must refuse, never read as "none", because "none" is the answer that lets the guarded action run. Ask: what does the guard answer when its call fails, and does that answer let the action through?
