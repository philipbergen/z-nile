---
title: Check a stand-in before logging it
when: build
tags: [verification, gate, evidence]
check: When a log says a check was skipped because another run covered it ("the same tree as X"), is `git diff --stat X <base> -- . ':!*/.tracker/**'` empty, and if not, does the log name the run that really stands in?
---
A skipped check logged with a stand-in nobody checked records a false fact: the reviewer, and later readers of the log, trust a run that tested another tree.

**Why:** R0059 code review 001 F2: Phase 0's full gate was skipped "because #156's head (the same tree but tracker files) passed it minutes before"; #156's head differed from the branch's base in 17 non-tracker files (781 lines). R0056's Phase 0 log line leaned on main's CI the same way.

**How to apply:** before logging a stand-in, diff its tree against what you skipped, outside the tracker folders. If the diff is not empty, log the check as skipped and name the later run that covers it (here Phase 3's full gate on the branch).
