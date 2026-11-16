---
title: A not-stacked stale line means main moved during the review
when: build
tags: [review, trace, stack]
check: Does a failing ./zn trace --check name a commit that came after the table, or does it say the layer is not stacked on the layer below, and if it is the second has origin/main moved since the skeleton was committed?
---
A stale line that names a commit means that commit came after the table. A line that says the layer is not stacked on the layer below means `origin/main` moved during the review, and it brings one "did not run green for this stack" line for every `check.sh` the table cites. Those lines are one cause. The reviewer cannot restack, so the check cannot pass in that review; the executor restacks, sets `Commit:` to the new finish commit, and runs the check again.

**Why:** R0109 final review 001 F2. `./zn trace` fetches, and `origin/main` moved 30 commits while the review ran. The check printed twelve lines, the first "not stacked on the layer below" and eleven "did not run green", and none of them named a commit. The same table was current against the stack's base.

**How to apply:** read the first stale line. When it says the layer is not stacked, say that `main` moved and name the one restack, instead of one finding per `check.sh` line. The restack gives a new finish commit, so `trace.md`'s `Commit:` is set to it before the check is run again.
