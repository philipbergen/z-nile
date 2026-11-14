---
title: A case that needs two processes to overlap, or a child to outlive something, holds it on a marker, never a sleep
when: both
tags: [specs, timing, processes]
check: Would this case still pass if the held process had simply finished (a broken lifeline, a run that never overlapped), and is every hold bounded so a wrong implementation fails instead of hanging the suite?
---
A fixed sleep makes overlap a matter of timing. Under load, a 3 s sleep against a 2.3 to 3 s start-up doesn't overlap, and a 30 s sleep lets a broken lifeline pass whenever the case around it takes longer. A marker file that the case removes once it has seen what it waits for (a `waiting for pid` line, a logged pid) makes the overlap happen by construction.

**Why:** c0165 design review 002 F1 and F5. The concurrent, failed-wait and timeout cases rested on 3 s and 30 s sleeps, and the orphan case's "runner is gone" assertion would have passed for a runner that merely finished its sleep.

**How to apply:** hold on a marker (optionally only for runs with an environment flag, so a waiter's own run doesn't hold), release it when the event is seen, bound every hold to a fixed number of polls, and assert "gone" while the marker still holds.

**Also:** c0279 design review 002 F2: a poll bounded by summing the `task.wait` it asked for does not count its own commands (600 `kill` execs cost 1.1 s of 20 s at load 10 and far more at the loads this repo sees), and the time before the poll starts grows with load too, so a grandchild's `sleep 120` ended inside the poll and a broken kill passed. Check: is the hold compared with the poll's wall time plus everything before it (bound the poll on the wall clock and make the hold an hour, or hold on a marker)?
