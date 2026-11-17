---
title: An answered code review is not run again to reach approve
when: build
tags: [z-work, review, engine]
check: When `./zn work next` still says "Answer the open code review ... until its verdict is approve" after every finding of the one review-NNN.md is answered (fixed with consequences, refuted or deferred) and committed, is the stack carried on to zz-execute Phase 5, with anything refuted or unclosed under `## Open to the human`, rather than a second reviewer started to flip the verdict?
---
`./zn work next` reads only the verdict of the highest `review-NNN.md` (`workread.reviewState`): anything but `approve` is "open". zz-execute Phase 4 and zz-review say there is one code review and one revision, and a second review of the same kind is refused, so a raft whose review said `changes` never reads as resolved there, however completely it was answered.

**Why:** R0110 (2026-11-16): review-001 had one high and two medium findings, all fixed on layer 1 and answered in refute-001; `work next` kept printing the review step. Starting another reviewer would have broken the one-round rule, and stopping would have left a finished stack waiting on nothing.

**How to apply:** answer the review once (refute-NNN.md, harvest, lessons), put any refuted finding, unclosed high or failed Judged criterion under `## Open to the human`, then follow zz-execute Phase 5 by hand (trace skeleton, final review, `./zn trace --check`); `./zn done` judges the code review by its answers, not its verdict. Say in the report that `work next` stayed on the review step.
