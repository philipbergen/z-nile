---
title: A reasoned row's reason is a claim the reviewer can test
when: design
tags: [mutants, specs, review]
check: For each Rules and mutants row marked `reasoned`, is its stated reason (why the mutant cannot be observed, or why no case is needed) true of the frame, the events and the public API, checked by trying to observe it? Before calling a mutant observable only through a long play sequence, has the hand-set state the spec's neighbouring cases already use (flipping a status or a flag) been tried?
---
`reasoned` lets a mutant go unkilled on the author's word. A reason such as "no public observation tells X" is easy to write and often false: the frame or the events carry more than the author remembered.

**Why:** f0126 design review 001 F2: row G1 said no public observation showed which maze a member's ghosts walk, but ghost positions are in every frame, and a ghost standing in a hole shows it; a seed search found one in seed 28.

**How to apply:** before marking a row `reasoned`, try for a few minutes to observe the mutant through the frame, the events and a seed search; write down what was tried. If it can be observed, write the case; if not, say exactly why, so the reviewer can check the claim.

**Also:** f0147 design review 005 F2: the eaten ghost's carry was called observable only after a full eyes run; flipping the ghost back to blue by hand, as the neighbouring cases do, observed it in five lines.
