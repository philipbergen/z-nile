---
title: A rate limit in a read policy states how long the smallest audience waits for each first answer, and a spec bounds it
when: design
tags: [proxies, budgets, latency]
check: For each allowance or token bucket a design puts in front of reads, with one player (the smallest audience), how long does the Nth distinct thing they ask for wait for its first answer (each board, each card, each tab, at the cadence the screen asks), is that number stated in the design and bounded by a spec on the real reader, and does the lever chosen to meet it keep every budget the allowance exists for?
---
A per-player rate is easy to defend against the experience's budget, and it is also a statement about latency: with one player it is the slowest the feature ever answers. Read bounds alone ("never more than N reads a minute") pass a design whose lone player waits half a minute for each board.

**Why:** f0206 design review 001 F3: at 1.5 refreshes a minute per player and a burst of 4, a solo player bringing each day board to the front waited 34 to 36 s per board on LOADING, and no criterion said how long was acceptable.

**How to apply:** write the first-answer bound for one player as a measurable proxy (here: every card's board the first time its tab is chosen, within one client retry), pin it in the spec that runs the real reader, and pick the lever (a per-server floor, a burst sized to the distinct things, a reserve kept for first answers) whose cost against each budget the design restates.
