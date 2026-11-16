---
title: A wrapper that reads a child's per-item results also honours the child's exit status
when: both
tags: [processes, results, guards]
check: Which failures does the child report only through its exit status (a guard that fires after every item passed), and does the wrapper count them before it trusts, records or reuses any per-item result from that run?
---
A runner can fail a run after every spec has passed and written its record: the browser guard fails the run when any spec opened a browser, and the tripwire when the repository changed during the run. Both report only through the exit code. A wrapper that reads only the per-file records calls that run green and stores its passes for later runs to reuse.

**Why:** c0165 design review 001 F1. The prototype's orchestrator ignored the runner's exit code. A spec that opened a browser made the runner exit 1, the orchestrator exited 0, and the next run printed `reused`.

**How to apply:** record passes only from a child that exited 0. A non-zero exit whose records show no failure is a failure the records can't attribute: count the run failed, record no pass, and say so. Add a case where a guard fires after every item passed.
