---
title: An outcome that makes a command repeat by itself states its limit
when: design
tags: [capture, retry, scope]
check: For every outcome in the idea that has a command try again by itself (retry, poll, merge again, gate again), does the idea say how many times, or that there is no limit, and what the command says when it gives up?
---
"X does it again by itself" reads as complete and is not: unbounded, it can spend a gate per loop with nobody watching; bounded, it adds a refusal the idea did not list. Either way the design has to stop and ask the user, because a limit changes the captured outcome. The idea step is where that is cheap to settle.

**Why:** d0331 (Finish refuses layer one when main moved), 2026-11-14: the idea step added "`./zn done` merges onto the new tip, runs the gate again and pushes again itself" beside "refuses for main's sake only when that merge conflicts or the gate … is red". Neither the draft nor its one challenge asked how often. Design stopped to ask the user, who answered "Stop after 9", which is also a third refusal the idea's own list excluded.

**How to apply:** at capture, read each outcome for a verb the command performs again on its own. Put the limit and the giving-up message in the idea text before `./zn idea` runs; when challenging an idea, ask for both wherever they are missing.
