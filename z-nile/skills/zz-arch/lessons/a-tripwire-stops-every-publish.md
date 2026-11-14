---
title: After a tripwire, nothing an agent runs publishes
when: design
tags: [tripwire, publish, safety]
check: Does any step a skill prescribes after a stop condition (land the green layers, publish a block, pull the main checkout) also run after a tripwire, and if so, is it the person who runs it once the checkout is checked?
---
A tripwire means the repository's remotes, config or history may no longer be what they were. A command that publishes or pulls then acts on whatever `origin` names by then.

**Why:** c0250 design review 001 F6: the new escalation steps (`done --through`, then `block`) applied to every stop, the tripwire included, so a worker would merge, push and pull right after `REPOSITORY CHANGED`.

**How to apply:** after a tripwire the agent writes its note and stops; the person checks the checkout and files the block; refuse the tripwire reason in an agent session.
