---
title: Search the backlog for the same failure before capturing it
when: both
tags: [capture, duplicate, backlog]
check: Before `./zn new`, did a search of the open issues for the failing function, file and message (`grep -rl` over the roots' `issues/`, done excluded) find no item that already describes this failure?
---
Two terminals that hit the same tooling failure on the same day each capture it unless one of them looks first. Both captures are then challenged, claimed and designed in parallel, and one design is thrown away.

**Why:** d0333 (2026-11-14, captured from c0306's prototype) and c0343 (captured hours later from R0101's stuck `done`) described the same three path rules refusing the raft's `spend.md`. Both were claimed and both got specs, a prototype and a mutant run before the designer of d0333 met c0343 in the tracker. The user ruled "Keep d0333 (Recommended)" and c0343 was withdrawn.

**How to apply:** before `./zn new`, grep the open issues for the names in the failure: the function (`isPostFinishPath`), the file (`spend.md`) and the message ("touches non-tracker file"). A hit that describes the same failure gets the new evidence as a note; a claimed one gets a message to its holder. Capture only what no open item covers.
