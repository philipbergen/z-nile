---
title: A guard's record with several honest writers is checked by what it guards, never by equality
when: design
tags: [concurrency, detection, state]
check: Who else legitimately writes this record (another run, the user's command), and does the guard re-check its subject from its own copy instead of failing when the record moved? Can two writers race it backwards?
---
A run that compares a shared record (the watermark) for equality with its own copy treats every other honest writer as tampering: two dispatchers at once tripped each other, and a user's `vet` during a run would too. Re-check the subject (vet `main` from the run's own copy, whatever the file says), so a tamperer is still caught by what it changed, and make the shared record move only forward under a lock, so two writers can't set it back.

**Why:** c0117 design review 004 F1.

**How to apply:** an in-memory copy for the run; a forward-only, locked write (ancestor check); spec two runs at once, a deleted and a rewritten record, and an older write over a newer one.
