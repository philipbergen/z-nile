---
title: A fake's keepalive must not let the step end by itself
when: design
tags: [fakes, heartbeat, stall, stop]
check: When a fake gains a heartbeat (or any output that keeps a stall detector quiet), how does the step end if the code under test does nothing, and is the outcome then different from the one the case asserts? If the fake can run out and exit, can an exit-time cleanup produce the asserted outcome, and does the fake instead go silent after the action and hold longer than the detector?
---
A heartbeat that runs until the group dies keeps the step alive through the fake's own `sleep`; when the fake then exits, the supervisor's cleanup kills what is left and the runner maps "failed plus the stop marker" to `stopped`, so a `dispatch stop` that kills nothing passes the stop case. The old fake, silent after the stop, caught it as `stalled`.

**Why:** c0279 design review 001 F3.

**How to apply:** after the action under test the fake stops all output and holds far longer than the stall limit of the case's issue; a mutant that makes the action a no-op must fail the case's outcome assertion.
