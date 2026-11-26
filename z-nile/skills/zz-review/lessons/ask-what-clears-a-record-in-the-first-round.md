---
title: Ask what clears or replaces each new record in the first round
when: both
tags: [review-rounds, records, state]
check: For every record a slice adds, did the first round list each operation and each request field that removes or replaces it, and answer what each leaves behind?
from: f0421 code reviews 005 and 006, 2026-11-24
---
A review that checks the new rule on the path it was written for finds the path around it one round late. For any record the slice adds, the first question is what clears it, not only what writes it.

**Why:** f0421 code review 006 F1 (2026-11-24): round 1 of the slice (review 005) fixed "a registration with no model" and the design then said "only a new process changes the model". Round 2 found that a registration with another session id also replaced the record and released the claim; the session branch was older than the slice and round 1 had not asked.

**How to apply:** in round 1 list every command, branch and request field that removes or replaces the record (a session change, a re-register, `ZN_WORKER`, `ZN_WORKER_PID`, a `gone`), and run each as a probe. Say what the record does not cover.
