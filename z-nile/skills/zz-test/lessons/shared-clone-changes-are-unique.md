---
title: Each case's commit in a shared fixture clone makes a change no earlier case made
when: both
tags: [specs, fixtures, git]
check: When several cases of one spec file commit in the same fixture clone (`other`, a race helper, a stand-in), does every commit write a path or content that no earlier case wrote, so none is an empty commit that fails before it pushes?
---
Cases of one spec file share their fixture's clones. A helper that writes `raced-$n.txt` with the content `$n` makes a real change in the first case and, in a later case that counts from 0 again, the same file with the same content: `git commit` finds nothing to commit, the helper exits non-zero before its push, and the case fails for the fixture's reason (here as "the push failed (origin/main did not move)").

**Why:** c0258's prep (2026-11-15): `retries.spec`'s second case reused the first case's race-file names in `other`, so its first race commit was empty and the land under test saw a push failure with `main` unmoved.

**How to apply:** put the case in the name (`raced-<case>-$n.txt`, from a per-case counter or fixture path), or derive the content from something only that case has.
