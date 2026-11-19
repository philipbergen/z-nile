---
title: A "flagged for the user" sentence has a bullet under Open to the human
when: design
tags: [raft, open-to-the-human, escalation]
from: R0100 design review 001 F3
check: Does every sentence in the raft that says the user must decide have a ruled `- F<n>:` bullet under `## Open to the human`, and is the section free of placeholders?
---
The dispatcher and `./zn ready` read only bullets under that heading; a placeholder there reads as no question.

**Why:** R0100 design review 001 F3: Risks said the z-work gap was "flagged for the user in Open to the human", and the section held `@@OPEN@@`.

**How to apply:** for each "the user decides" sentence write one bullet in the form `- F<n>: <ruled answer>`; if nothing is left open, say so in prose and write no bullet.

**Note (R0093 design reviews 002 F1 and 003 F2):** an open point is a bullet only when its id is `F<n>` or `JC<n>` (`openlist.pending`); `- O1:` bullets are invisible. `./zn ready` and `./zn work next` refuse while a refuted finding or an unfixed high of the latest raft review (the highest `design-review-NNN.md`) has no ruled bullet of its id; `./zn status <R> prepared` runs the same check inside its publish on origin/main's copy of the raft folder, so it does not see a review the rafting branch adds (R0093, 2026-11-18: it passed with an unanswered high); earlier rounds' bullets and open mediums are read only by `./zn dispatch`. So a hold rests on the latest round: when a new record forces a new review, carry the still-unruled bullets as one high finding of that review, answered open (z-raft/regroup-carries-earlier-coherence-findings).
