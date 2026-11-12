---
title: A spec's stand-in for a session or owner process is reaped, so `kill -0` can say it ended
when: both
tags: [processes, specs, shell]
check: Where a spec or a loop decides "that process ended" with `kill -0`, is the process one whose parent waits for it (or init), and does a case end it and see the loop stop?
---
`kill -0` succeeds on a zombie, so a child its parent never waits for looks alive for as long as the parent lives.

**Why:** c0275 prep (2026-11-12): the beater proof backgrounded `sleep 4 &` and then `exec`ed the beater, which polled that pid; the sleep stayed a zombie of the exec'd shell and the loop ran 90 s to its bound.

**How to apply:** start the stand-in as `p=$(sleep 4 >/dev/null 2>&1 & echo $!)` so init reaps it, and assert the loop stops within seconds.
