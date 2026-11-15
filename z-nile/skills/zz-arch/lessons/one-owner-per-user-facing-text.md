---
title: A user-facing text has one owner, called and not copied
when: both
tags: [texts, duplication]
check: Is any sentence the user reads written in two places (an engine string and a module string), so that a later edit changes one?
---
Two copies of one message drift: one ending of the lost-work text differed between the give-back and the carried move.

**Why:** R0100 review-002 F3 (`hb.lostText` rewrote what `heartbeat.lostText` owns).

**How to apply:** make the engine call the module's text function and let the specs pin the module's strings.
