---
title: A claimant reads its own fixed facts before it claims
when: both
tags: [locks, claims, polling]
check: Between taking a claim (a mkdir, a lock file) and recording who holds it, does anything run besides the writes themselves, and does a waiting loop re-read facts about itself (its pid, its start id) that cannot change while it waits?
---
The gap between a claim and its record is the window in which another process sees an unowned claim and may clear it. A subprocess there (reading one's own start id, say) widens the window by its run time; inside a wait loop it also repeats on every step.

**Why:** R0047 code review 001 F1: the takeover waiter ran perl for its own start id after creating the takeover folder and before writing its `pid`; a 3 s perl let a second waiter remove the takeover as unowned (2 s), and the first then crashed writing into the removed folder. The read also ran on every 0.1 s step of a 240 s wait.

**How to apply:** read your own facts once, before the loop and before the claim, and pass them in; keep the claim and its record a few writes apart; count the reads in a spec (`testing/count-calls-in-poll-loops`).
