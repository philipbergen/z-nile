---
title: A copied or merged module brings its promoted cases with it
when: design
tags: [acceptance, regression, copy]
check: For each promoted spec of the module this design copies or merges, which of its cases still describe behaviour the new module keeps, and where is each one now: ported to the new module's specs (on a stub strong enough to reach it), or named with the reason it no longer applies? Is "they test the old module" the only reason given for any of them?
---
When a design copies a module into a new home or merges two modules into one, every case in the old module's promoted specs that tests behaviour the new module keeps is ported to the new module's sequestered specs, or named in the design with the reason it is dropped (a client view the new module does not have, a source-text pin). "They test the old module" is not a reason: once the old copy is deleted, its promoted specs go with it, and nothing in the repository pins the rules they held.

**Why:** f0197 design review 001 F1: the generic `Boards` adapter merged pickman's `HiscoreStore` and lobby `Boards`, and the design dropped pickman's three adapter specs as a group. Nine wrong adapters (no size-50 retry, an unreadable row skipped, waiters never answered, the failure wait ignored, a wrong budget, a departed player answered, pending never released, a failed read answering empty rows, an all-time board with no list failing) passed every f0197 spec. Those rules had taken R0011, c0128 and d0124 several review rounds to settle.

**How to apply:** list the old module's promoted specs (`grep -rlF` for its path, and the selector), walk each case, and sort it into ported or dropped-with-reason in the Unknowns. Port onto a stub that can do what the old one could (hold a read, set the clock, fail one key, reject a page size, record request types), and run the old module's known mutants against the new one.
