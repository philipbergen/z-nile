---
title: A `fail` inside a pcall is not caught: it exits the process
when: both
tags: [errors, luau]
check: Does a pcall wrap code that calls the engine's `fail` (which exits the process), so the pcall cannot catch it?
---
In this engine `fail` ends the process, so `pcall(f)` around a body that calls it protects nothing. Use a reader that returns its failure, as `hb.beatPaths()` does, and run only the pure judge inside the pcall.

**Why:** R0100 review-002 F2 (`stop` wrapped `hb.judgeAll(originPaths())` in a pcall, and `originPaths` fails).

**How to apply:** read through the function that returns the failure, branch on it, and add a case with an unreadable origin.
