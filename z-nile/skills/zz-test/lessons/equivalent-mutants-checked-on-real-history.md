---
title: A mutant called equivalent must be equivalent on real history, not only on the fixture
when: design
tags: [mutants, equivalence, fixtures]
check: For each mutant dropped as equivalent, is there a real history (a root move, a re-add, a merge commit) in which it gives another answer, and does a fixture case with that shape kill it?
---
A mutant that survives every case is not equivalent until nothing the code can meet tells it from the original; a fixture with one shape proves only that shape.

**Why:** c0280 design review 001 F2: "delivered newest done add" was called equivalent alone because no fixture had a second add under `done/`; real done items have one (the root move of R0048), and the mutant printed that move as the delivery.

**How to apply:** for every survivor, name the real-history shape that would separate it, add that shape to a fixture, and keep the mutant in the runner; call one equivalent only with the reason it cannot differ on any tree.
