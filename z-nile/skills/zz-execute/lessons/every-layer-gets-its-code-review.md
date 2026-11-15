---
title: Every layer of the stack is code-reviewed before the final review
when: build
tags: [review, layers, done]
check: Does each layer of the stack have a review-NNN.md whose Inputs line names that layer, and which command would notice if one did not?
---
`./zn done` and `./zn trace` do not look for a layer's code review; a layer can go from its finish to the final review with none, and only the final reviewer notices.

**Why:** R0100 (five layers). Layer 3 (c0275, automatic heartbeats) was finished, restacked and pushed three times with no code review: reviews 001, 002, 003 and 004 named layers 1, 2, 4 and 5 (the rounds followed the order the layers were built, and layer 3's slot was skipped when a headless review died). The final review found it (F4), and the review it caused (review-005) found a medium finding and five lows in 1,774 lines.

**How to apply:** after each `./zn finish`, review that layer before starting the next, and before the final review list the layers against the review files (`grep -l 'R0100/3/c0275' review-*.md`). A reviewer that cannot start (a headless dispatch that died) is rerun as a subagent in the same round, not skipped.
