---
title: A new read on a path every fixture spec takes is measured, with and without it
when: design
tags: [cost, specs, fixtures, gate]
check: Does the design add work (a fetch, a read, a build) to a path that fixture repositories take (a publish, a land, a sync, a board rebuild), and was the slowest affected spec timed with and without it on the prototype, in the same run, with the whole affected set run rather than a hand-picked list?
---
A guard that makes the real checkout silent does not make a fixture silent: fixtures under `.cache` are unguarded and do the work on every call, so one extra read multiplies by every spec that publishes.

**Why:** c0276 design review 001 F4: the board's verdict reads were argued free "in the spec runner, a protected checkout"; fixtures read them on every rebuild and three publish-heavy specs ran 15% to 40% longer; the prep had run 46 hand-picked files although the affected set was the whole suite.

**How to apply:** run `z-nile/check.sh --affected` on the prototype, time two or three publishing specs with the new work stubbed out, record the numbers, and skip any read a caller has just made.
