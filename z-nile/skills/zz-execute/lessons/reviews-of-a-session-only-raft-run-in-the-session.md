---
title: Reviews of a session-only raft run in the lead's session
when: build
tags: [dispatch, reviews]
check: Does any check of this raft fail inside a dispatched step, and where will each of its reviews run?
---
R0103 said its executor must run in a user-opened session (E4: `trace-land.spec` is red in a dispatched step), but its final review was started through `./zn dispatch zz-review`, so the reviewer could not run AC10.

**Why:** R0103 final review 001 candidate.

**How to apply:** when a raft's document says a check is red in a dispatched step, start its reviews as a subagent in the lead's session, or accept that the reviewer cannot run that check and name the run that did.
