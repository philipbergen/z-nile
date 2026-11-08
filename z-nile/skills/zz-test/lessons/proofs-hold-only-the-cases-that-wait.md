---
title: Moving real-time cases to one-time proofs moves only the cases that actually wait
when: both
tags: [specs, proofs, speed]
check: For each case in a check.sh-only proofs folder, does it wait for a real limit, and if not, why is it not a promoted spec?
---
A proofs folder is not promoted, so instant rules put there lose their permanent guard after `done`.

**Why:** f0265 design review 005 F3: the takeover race and fold's beat moved with the waiting cases and were left unguarded.

**How to apply:** split by cost, not by file: instant cases stay in `acceptance/`, only those that wait go to `proofs/`.
