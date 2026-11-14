---
title: A proof that only check.sh runs is protected only if check.sh pins it
when: design
tags: [sequestration, proofs, check]
check: Is every file a sequestered check.sh runs either under acceptance/ (sequestered, promoted) or pinned in check.sh by a hash, so that changing it during execution fails a named criterion?
---
The sequestered set is `check.sh` and `acceptance/`. A spec kept elsewhere (a proofs folder for real-time cases) can be edited during execution without any guard noticing, so a wrong implementation can pass the criterion that runs it.

**Why:** c0265 design review 009 F1: the real-time proofs behind AC4 and AC5 lived in `proofs/`, outside the sequestered set.

**How to apply:** pin each such file with `git hash-object` in the check that runs it, skip the check after `done`, and re-pin as the last step of prep.
