---
title: Each joint between members is killed by a promoted member case, or it goes to the human
when: design
tags: [raft, rc, joint, mutants, promotion]
check: For each joint the Whole-raft design names (a listener one member exposes and the other wires, a boot order, a shared remote), which promoted member case turns red when it breaks? Was that shown by running the joint's mutants against the members' acceptance specs alone, on the stacked prototype, before any raft check was written?
---
A joint proved only by a raft check is unguarded once the raft is done: RCn lines are not rerun, and the next issue to edit the shared file (a Main every feature boots from) meets no red spec. Each member's own spec stubs the other side of the joint, so "both members' specs pass" does not show the joint holds.

**Why:** R0117 design review 001 F1. Of twelve joint mutants of f0205's carousel and f0208's PLAY, eleven were killed by member cases. One survived every member spec: the client's Main booting PlayButtons before CarouselView, which leaves every card without buttons. f0205's interface had assigned that proof to f0208's acceptance, and neither place spec pinned the order.

**How to apply:** list the joints, write one mutant per joint on the stacked prototype, and run only the members' acceptance specs against each. Record a table of mutant, summary line and killing case. A survivor is a gap in the member the interface assigns the proof to: put it under `## Open to the human` with options (unfold and re-prep that member, a tooling chore, a later prep's case, accept). Never close it with a raft-only spec.
