---
title: Every old stop joins the new escalation, or is named as staying
when: design
tags: [escalation, stops, scope]
check: When a new path replaces an old stop signal, has every remaining stop of the old kind (an open list, a questions file, an exit code) been found in the skills and the engine, and does the design say for each whether it joins the new path or stays, with the user's ruling for any that stays?
---
A replacement that covers the signal it was named after but not its siblings leaves a captured outcome unmet, and a stop that still uses the old path keeps the state local where the new one publishes it.

**Why:** c0250 design review 001 F1: the design replaced `questions.md` with a published block, but left the open-list stop (`## Open to the human`), the capture's first wall ("review rounds exhausted"), local; in execution, a resolve then wrote no ruling and the raft blocked again.

**How to apply:** grep the skills and the engine for every stop of the old family (exit codes, files, document sections) and list each one in the design with its new path.
