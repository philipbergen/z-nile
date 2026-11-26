---
title: A machine-wide limit sits where the expensive work starts
when: both
tags: [gate, queue, limit, entry-points]
check: Is a limit on expensive work (one gate at a time) enforced inside the one place every path into that work passes through, and has every caller been listed and tested, rather than at the command people usually type?
from: code and spec reviews of #744 to #748 and d0434, 2026-11-21 (filed in #749)
---
A limit put on the usual entry point misses the other ways in. The largest runs are often started by another command.

**Why:** d0426 (2026-11-21, code review): the queue covered check.sh typed by hand but not ./zn finish, which runs the biggest gates a worker makes, nor a top-level tests/run. It moved into the outermost check.sh block and the top-level runner, with a nested run recognised and let through.

**How to apply:** grep for every starter of the work, put the limit at the common point, and add a spec per entry that shows it queues.
