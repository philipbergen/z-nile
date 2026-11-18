---
title: Rerun a branch-only red after finish
when: build
tags: [gate, layers, verification-log]
check: For each red the Verification log blames on the layer's own unfinished state (no watch file yet, an unpromoted spec), was the spec rerun after `./zn finish` and its result appended to the log?
---
Before `./zn finish` a layer's own acceptance spec has no watch file, so the selector returns it for any path and `c0185/selector` fails on that layer alone (d0297). Such a red is not the change's, but a log that only says "red on this branch" reads as a stop the executor walked past.

**Why:** R0132 (d0413, 2026-11-17): the full gate of Implementation step 3 was red in `c0185/selector` on the layer only. The log explained the cause but did not show it cleared; code review 001 F1 reran it after `finish` (2 passed) and asked for the line.

**How to apply:** Explain the cause in the log when you meet the red, run the spec again once `finish` has written the watch file, and append the result. If it is still red, it was not the layer's state: stop.
