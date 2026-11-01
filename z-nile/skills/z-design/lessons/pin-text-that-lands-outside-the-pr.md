---
title: Text a raft lands outside its PR is pinned by a one-time digest
when: design
tags: [sequestration, capture, check]
check: Can the executor change what lands (an unsequestered script under experiments/, a hand edit, a capture `land` the PR diff doesn't show) and still pass every criterion? If so, does check.sh pin the landed text by digest, at done only, with values that change at capture time (ids) masked?
---
Sequestration covers `check.sh` and `acceptance/`. A script prep writes under `experiments/` is not sequestered, and a capture's `land` puts its documents on main outside the raft's PR, where the code review doesn't see them. Checks that only look for a quote or a pointer pass a thinned text.

**Why:** c0190 design review 001 F2: AC1 to AC4 passed on 27 Problems holding only the user's quote and a pointer; check.sh's AC6 now pins each landed title, Problem and Non-goals by SHA-256, ids masked.

**How to apply:** compute the digests on prep's prototype with the same normalisation the check uses (prove they agree), and keep them in check.sh, never in a promoted spec (later preps add detail).
