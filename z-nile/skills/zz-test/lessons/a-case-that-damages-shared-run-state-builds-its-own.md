---
title: A case that damages shared run state builds its own copy of it
when: both
tags: [fixtures, specs, concurrency]
check: Does any case write into something every other spec file of the run reads (a template, a cache, a shared folder), and what does the next worker see?
from: c0178 design review 005 F1, 2026-11-24
---
"This case runs last" holds inside one file only. A run is one worker process per spec file, several at a time, and they all read the same run state.

**Why:** c0178 design review 005 F1 (2026-11-24): the template spec's last case took the run's own template (`trackerfix.template(false)`), wrote a file into it and left it, so every later fixture of that gate without `noLessons` would refuse with `template changed`. Nothing in the ticket showed it: AC1 ran the file alone and AC3 ran the suite before the spec was promoted. Deleting the file at the end would not help, since the folder's times still changed.

**How to apply:** the case builds a private template through the tooling seam, damages that one, and expects the next clone from it to refuse. Add a closing assertion that the run's own templates still pass the check, and state in the design that no spec writes into state it did not build.
