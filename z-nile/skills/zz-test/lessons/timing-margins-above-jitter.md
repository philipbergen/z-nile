---
title: A promoted case never compares measured times closer than a loaded machine's start-up jitter
when: both
tags: [specs, timing, flakiness]
check: At load 20, can this case's margin invert: does it compare measured durations or start times whose gap is smaller than a process's start-up jitter, or does it write the timing input itself?
---
Promoted specs run in every gate, often while other gates load the machine. Process start-up then varies by more than a second, so a case that orders files by their measured 0.1 s against 0.6 s sleeps, or by which started first, flips at random.

**Why:** c0154 design review 001 F2: the runner case scheduled by a record it had just measured (c slept 0.6 s, a 0.1 s), and checked start order with 0.1 s sleepers; at the loads measured that day (a `./zn` call 0.3 s idle, 2.0 s loaded) the order could invert.

**How to apply:** write the input the behaviour depends on (here a hand-written duration record) instead of measuring it, and give anything that must hold a slot a hold far above the jitter (3 s), checking only which items came first, never a measured gap. Run the case several times at the machine's current load before promoting it.
