---
title: Two pinned sentences that both pass can still contradict each other
when: design
tags: [raft, pins, captures]
from: R0070 design review 001 F1
check: Does the merged paragraph deliver every member's captured outcome, or does it only satisfy both pins?
---
Specs pin fragments, so two members' fragments can stand side by side in a paragraph that contradicts itself.

**Why:** R0070 design review 001 F1: c0189's pinned prototype rule sent a clone "into `$TMPDIR` or the scratchpad" beside c0194's "under `.cache/.tmp/`, never the system temp folder"; every pin passed and c0194's captured outcome was dropped.

**How to apply:** after the specs pass on the combined text, read the combined paragraph against each member's captured Problem.
