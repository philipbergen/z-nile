---
title: No check is red between the steps that use it
when: design
tags: [process, gate]
check: Does any check that runs between rounds or steps (the reviewer's own run, the gate, an acceptance check) depend on work the process does only at a later step?
---
If a step's output is checked but the step comes late in the process, every run of that check before then fails. Reviewers then report it, and a gate turns red. Do the work at the step that creates its input, or make the check run only after that step.

**Why:** R0040 design review 1 (F4): harvesting only after the final round left the raft's acceptance check (and later the coverage gate) red during every intermediate review round, which code reviewers run.

**How to apply:** for each new check, name when it first runs and who runs it (author, reviewer, gate, CI), and confirm its input exists by then.
