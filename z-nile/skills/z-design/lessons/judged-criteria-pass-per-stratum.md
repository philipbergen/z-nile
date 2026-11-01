---
title: A Judged criterion that samples passes per stratum, not in aggregate
when: design
tags: [judged, acceptance, sampling]
check: Does the rubric give each stratum of the sample its own threshold, so that a whole stratum (the one most likely to be gamed) cannot fail inside a passing total?
---
An aggregate percentage over a mixed sample lets one stratum be poor while the total passes, and the Checked criteria may pass on placeholders, so the Judged one is the only guard.

**Why:** c0112 design review 001 F10: JC1's 90% rule let three bad one-offs pass in a sample of 32.

**How to apply:** list the strata, give each a small-sample threshold (for example 7 of 8), say that a failing stratum is redone and re-sampled, and add a stratum for any outcome the Checked criteria cannot judge.
