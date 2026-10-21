---
title: A check must not pass because it found nothing
when: both
tags: [coverage, exit-codes]
check: Can this check pass because it found nothing to check, and does "not found" differ from "checked and clean"?
---
A coverage or validation check that treats "nothing found" as success passes when its input is wrong: a missing folder, a mistyped id, or a reader that skips a location. Make "not found" an error, or a different outcome from "checked, clean", and test both.

**Why:** R0040 design review 1 (F1): `lessons --uncovered R0040` printed `no reviews` and exited 0 for an item the reader never found, so the acceptance check on the raft's own harvest could pass with no harvest at all.

**How to apply:** for every check that can find zero things, write a spec case that names something that does not exist, and assert it fails or says so.

A check that loops over a list it computes (roots, items, files) must also fail when the list is empty or the command that computes it fails: c0115's AC14 looped over `lune run z-nile/roots` in a process substitution, so a failing command gave an empty loop and a pass. Count what the loop read, and fail on zero.
