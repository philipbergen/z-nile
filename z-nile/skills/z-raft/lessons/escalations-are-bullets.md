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
