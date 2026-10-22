---
title: A subprocess added to a poll loop has its calls counted
when: both
tags: [polling, subprocesses, mutants]
check: For each subprocess added inside a wait or poll loop, does a spec count its calls (or which inputs it was called for), and does the loop's timeout count wall time rather than steps?
---
A loop that counts steps (`waited += 0.1` after `task.wait(0.1)`) makes each step's own cost part of its timeout. A subprocess called once per item per step can stretch the wait many times over while every spec stays green.

**Why:** R0047 design review 003 F2: reading a start id before checking that the pid was alive would run perl for each of a stale lock's ~370 dead records on every step, stretching the 240 s wait about 20 times, and no case noticed.

**How to apply:** give the spec a way to see the calls (a stand-in that logs its argument and hands the call to the real tool) and assert which inputs were read; add the read-order mutant to Rules and mutants.
