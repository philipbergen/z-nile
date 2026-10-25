---
title: A step's result needs a landing place on every path that runs it
when: both
tags: [dispatch, headless, outputs]
check: For each step a dispatcher, a CLI or a subagent can run, where does its result land on each path (interactive, dispatched, headless), and who reads it from there? Does any path say "return it" with no caller to return to?
---
A mode written for one caller ("return the review markdown; the lead writes the file") loses its result when another path runs it. A dispatched or headless run has no caller: its text ends with the process, and the spend line that follows names nothing.

**Why:** c0117 design review 007 F1: under the dispatcher a stream review ran headless, zz-review's Stream mode told the reviewer to return its text and write no file, the runner kept only the token count, and the dispatcher looked for review files in the issue's folder rather than the raft's. The review vanished, and its `record:` line named no file and no issue.

**How to apply:** for each mode, write down where its output lands on every path that runs it, and give each path its own carrier (here: the dispatched reviewer writes `stream-review-<issue>-NNN.md` itself in the raft's folder, an interactive subagent still returns text for the lead). Pin each path with a case that finds the output where it should be.
