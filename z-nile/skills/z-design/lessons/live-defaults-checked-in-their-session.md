---
title: A live identity or default is checked in the session that runs the command
when: design
tags: [actor, defaults, sessions]
check: Where does a command that records who did it usually run (an agent session, a dispatched step, a plain shell), and what does its fallback record in each?
---
A fallback written for the plain shell (the git user) is wrong in the common case when most commands are run by an agent in the user's name.

**Why:** c0263 design review 001 F3: the actor fell back to `human:<git name>`, so every interactive agent command that forgot the flag recorded the user; the session's environment (`CLAUDECODE`, `CLAUDE_EFFORT`) already said an agent was running.

**How to apply:** run the command in each session that runs it and read what it records; add the session hint to the resolution order, and make the unknown case say `unknown`, not a plausible name. Specs that assert the human fallback clear the hint so a run inside an agent session stays green.
