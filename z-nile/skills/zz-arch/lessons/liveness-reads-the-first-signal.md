---
title: A step's liveness reads the first signal a tool starts, from whichever stream shows it
when: design
tags: [dispatch, liveness, adapters]
check: For a CLI the dispatcher watches for stalls, which output shows that a tool call has started, rather than only that it has finished, and does the adapter read that stream (stderr or a log) so a long tool call is not killed as stalled?
---
The dispatcher kills a step that shows no progress for too long. A CLI that writes a tool call to stdout only after the call finishes looks silent for the whole length of a long call, so it is killed as stalled while it is working.

**Why:** c0175's prototype (2026-11-15), experiment E6. opencode prints a tool on stdout only when it has finished, while its `--print-logs` stderr writes `evaluated permission=` when the call starts. The adapter gained an optional `feedErr` hook that reads that line.

**How to apply:** probe each new CLI with a long tool call and read which stream moves first. Feed that one to the liveness check, and name it as an Unknown if it is a log line the CLI could reword.

**Note (c0175 design review 001 F3, 2026-11-15):** count open tool calls; do not keep one running-tool flag. CLIs run tool calls in parallel, and the first `tool_use` of a batch to finish cleared the flag while a long sibling call, such as a full gate run, was still working. That call was then killed as stalled after 300 s.
