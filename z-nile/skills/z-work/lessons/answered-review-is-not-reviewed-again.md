---
title: An answered review is settled or due another round, never stuck on review
when: build
tags: [z-work, review, engine]
check: When `./zn work next` names round N+1 after an answered review, is it run, and at the maximum is the answered review taken as settled?
---
`./zn work next` used to read only the verdict of the highest `review-NNN.md`: anything but `approve` was "open", so a raft whose review said `changes` never read as resolved there, however completely it was answered. Since f0421 the rounds rule decides (`rounds.next`): approve settles; a round not approve and not answered waits for its answer; an answered round with a high or medium finding below the item's maximum is followed by round N+1 (`work next` says "run code review round N+1 of at most M"); an answered round with only low findings, or at the maximum, is settled and the stack moves on to the trace.

**Why:** R0110 (2026-11-16): review-001 had one high and two medium findings, all fixed on layer 1 and answered in refute-001; `work next` kept printing the review step, and neither a second reviewer nor stopping was right under a one-round rule.

**How to apply:** when `work next` names round N+1, run it (zz-review code mode, checking the answers); when it names the answer, answer it (refute-NNN.md, harvest, lessons) and put any refuted finding, unclosed high or failed Judged criterion under `## Open to the human`. The numbers are maximums: a settled review is not reviewed again.
