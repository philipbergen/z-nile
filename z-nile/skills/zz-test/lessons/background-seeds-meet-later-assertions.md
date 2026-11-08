---
title: A claim a fixture seeds in the background must be checked against every later listing assertion
when: both
tags: [fixtures, ordering, listings]
check: Does any item the fixture seeds (a never-beaten claim, a done item, a bystander) change what a later "first line", "empty output" or "not listed" assertion sees in the same spec?
---
An assertion about the first line, an empty list or an absent item is about every item the fixture holds, not only the ones the case set up.

**Why:** c0265 design review 001 F2: a seeded never-beaten claim was the most silent claim, so it sorted first and was listed where the spec expected nothing; no correct implementation could pass.

**How to apply:** after writing a fixture, walk each listing assertion and name what every seeded item contributes to it; assert on the case's own item (its line, its position relative to a named neighbour) rather than on whole outputs.
