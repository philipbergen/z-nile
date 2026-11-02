---
title: An adapter loaded with a closed module table breaks the next require
when: both
tags: [specs, adapters, stubs]
check: Does this spec load an adapter with a table of its modules that asserts on any other require, and which issues in flight add a require to that adapter (so their change would turn this spec red, and neither may edit the other's sequestered or promoted spec)? And for an adapter every feature touches (Main), is the harness open on every side: Logic features loaded as themselves (by name for one added later), sibling adapters and services as stand-ins, and stub instances that behave like Roblox (re-parenting to the same parent does nothing), so that a correct one-line addition keeps the case green?
---
`tests/place/touch-adapters.spec.luau` and f0110's sequestered `adapters.spec` load Controls through a hand-written `require` that asserts the module is in a closed table. A later issue that adds one `require` to Controls fails those cases, and because a promoted or sequestered spec is never edited during execution, "merge by hand" cannot fix it.

**Why:** f0126 design review 002 F1: f0126's `require(".../Logic/Picks")` in Controls made 5 of f0110's cases fail on the unknown module; f0126 then took the wire string through View, which those tables already load.

**How to apply:** in a new stub loader, fall back to the real Logic module (`@logic/<name>`) for any Logic require not stubbed, rather than asserting. In a design that adds a require to an adapter, search the specs (sequestered ones in other preps included) for loaders of that adapter, and either reach the value through a module they already provide or narrow them by a chore first.

f0126 design review 005 F2: `views.spec`, the first spec to load Main's source, knew only fifteen Logic features, refused any other sibling or service, and filed a re-parented child twice; five correct one-line changes (one more require, a new adapter, another service, a `fromScale` idiom, a reused model) each turned it red. It was opened on every side, and the mutation runner now runs those five as correct variants that must stay green.

d0124 re-prep (design review 006 F1): f0146 added a Logic require to FlowView and d0124's `adapters.spec` loader, a closed table, failed the executor. The first repair added the one missing module; the review found the table still closed (an extra unused Logic require in each of the five adapters made 0 of 25 pass). Repair the loader with the fallback, not with one more entry.
