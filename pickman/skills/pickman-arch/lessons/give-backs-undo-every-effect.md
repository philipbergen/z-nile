---
title: A give-back undoes every effect the use had
when: design
tags: [adapters, payments, counts]
check: When a design gives something back (a refund of a credit, an undo of a use), does it list every effect the use had (the credit spent, a count for the boards, a flag, a bound) and undo each one, only when the give-back is written, and never past the starting value?
---
A use of a credit often does two things: it spends the credit and it counts for something (a run's revives on the boards). A refund that restores only the credit leaves the count saying the run used what it gave back.

**Why:** f0201 design review 001 F9: `Wallet.refund` gave a revive back to the record but left the run's revive count, so a player who left during the revive's write was refunded and still shown on the boards with one revive used.

**How to apply:** for each give-back, write down the use's effects and undo each; undo the count only when the give-back's write succeeded (a failed one may be retried), never below 0, and only for the kind that counted; add cases and mutants for each of those.
