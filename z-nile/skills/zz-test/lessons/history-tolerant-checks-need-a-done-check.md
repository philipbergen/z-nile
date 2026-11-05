---
title: A history-tolerant promoted check needs an exact done-time check
when: design
tags: [specs, promotion, acceptance]
check: Can a branch that once had the right file and then broke it pass this criterion, and is the exact claim about the delivered tree in check.sh?
---
A promoted spec that must stay green while later work edits a file ("some version of it was right") cannot also prove what the branch delivers: a correct commit followed by a broken one still passes.

**Why:** c0183 design review 001 F1: designs.spec accepted any past version of each moved design, so a branch that changed a game rule and deleted a stub after a correct commit passed AC3.

**How to apply:** split the jobs. check.sh, which runs at done and never again, compares the delivered tree exactly (for example `shasum -a 256 -c` against pinned digests); the promoted spec keeps the tolerant rule against the same pinned values. Add the "right, then broken" mutant to Rules and mutants: it must fail the check and may pass the spec.
