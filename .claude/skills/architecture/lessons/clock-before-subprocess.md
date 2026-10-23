---
title: Name the clock behind every time you compare
when: both
tags: [time, subprocesses]
check: For every pair of times the design compares, which clock is each on (wall clock stamped once, wall clock rebuilt at read time, boot clock), what does a clock step or a slow subprocess do to each, and where a time is "now minus an elapsed time", is now read before the subprocess runs?
---
`os.time() - elapsed` with the clock read after the subprocess returns moves the result later by however long the subprocess took, so a slow run turns "started before" into "started after".

**Why:** R0047 design review 001 F4: c0127's first `startedAt` ran `ps -o etime=` and then read `os.time()`; a 3 s `ps` made a live holder recorded in the same second look like a reused pid, which would let a second run share the fixtures. The 2 s slack in the Design assumed the opposite order.

A time read from the kernel is not automatically fixed: macOS stamps a process's start once, at fork, but Linux rebuilds it as `btime` plus ticks since boot, and `btime` follows the wall clock, so a clock step moves it (R0047 design review 002 F2).

**How to apply:** read the clock first and say what the slack covers. Prefer times stamped once (a file's mtime, macOS's start time), and for each compared time write down which clock it is on and what a step of either sign does to the comparison.

Better still, don't order two clocks at all: identify the thing by a value stored when it was recorded and compared for equality, such as a process's (pid, start id) or a file's (inode, mtime). Equality survives clock steps and needs no slack (R0047 design review 003, the user's choice of start ids).
