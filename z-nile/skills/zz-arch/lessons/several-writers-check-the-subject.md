---
title: A guard's record with several honest writers is checked by what it guards, never by equality
when: design
tags: [concurrency, detection, state]
check: Who else legitimately writes this record (another run, the user's command), and does the guard re-check its subject from its own copy instead of failing when the record moved? Can two writers race it backwards?
---
A run that compares a shared record for equality with its own copy treats every other honest writer as tampering: two dispatchers at once tripped each other. There is no shared file. Each process judges `main`'s commits from the tip it started from, so tracker state another run pushed is not a trip, and a rewrite of `main` during the process still is.

**Why:** c0117 design review 004 F1.

**How to apply:** each process judges `main`'s commits from the tip it started from. There is no shared file. Tracker state another run pushed during this one is not a trip; spec two runs at once.
