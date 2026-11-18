---
title: A cost is measured per event at the largest case, not only as an average per tick
when: design
tags: [scalability, experiments, performance]
check: For each expensive call the design makes on an event (a respawn, a join, a roll, a placement), was one call timed at the largest arena and the latest map, and how many can land in one tick? Does the Scalability section report those, not only a per-tick average that spreads them out?
---
A per-tick average over a long run hides a call that happens once a second: 0.8 ms a tick can be one 45 to 100 ms call spread over 30 ticks, and that one call stalls every player's frame.

**Why:** f0211 design review 001 F5: E2 reported 0.8 ms per 1/30 s tick for a 24-snake arena; one brute-force respawn (`World.safest`) cost 45 to 104 ms there. The redesign (two distance fields, O(side²)) brought it to 2.6 ms, measured per call in E7.

**How to apply:** for each event-driven call, an experiment times one call at the largest size and latest map with a pass line (under a few ms in Lune), and names how many can coincide in a tick; the Scalability section quotes those numbers beside the average.

**Note** (c0249 design review 001 F5): measure a guess's cost at the input the shipped caller actually sends most, not at hand-picked cases. c0249's E3 timed three chosen moves, while the Omarchy app's drop at the end of a column sends `last`, which ranked all 194 backlog issues and wrote 388 files in one commit. Ask: for each caller that ships with the design (an app hook, a loop), which input does it send, and did an experiment measure that one?
