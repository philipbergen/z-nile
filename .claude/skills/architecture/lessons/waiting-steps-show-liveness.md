---
title: A step that waits on another step must show it is alive to whatever watches it
when: design
tags: [process, timeouts, headless]
check: When this step runs a long child (a nested review, a gate), what resets the parent's stall clock, and what is the CLI's own limit on one command?
---
A headless author that runs its review as one shell command is silent for as long as the review takes: the dispatcher's stall clock (`tool_seconds`) and the CLI's own command timeout (Claude Code: 120 s by default, 600 s at most) both kill it on ordinary input. The child must signal liveness the parent counts (a heartbeat file its runner writes while its CLI prints), and each CLI's command limit must be measured and raised, or the skill must poll a background child.

**Why:** c0117 design review 004 F2: no case covered a review longer than a few seconds, and reviews here take a median of 4 minutes and up to 29.

**How to apply:** a heartbeat both ways in the runner, the CLI's limits in the step's environment, an experiment per CLI, and a spec with a child longer than the parent's stall limit (and a quiet child that still stalls).
