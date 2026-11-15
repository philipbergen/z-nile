---
title: A parse of a process output's last line reads a bounded tail, never a lazy pattern over the whole output
when: both
tags: [luau, patterns, performance, runner]
check: Does any pattern over a whole process output (a worker's stdout, a log) pair a lazy `.-` with a following `[^\n]*` or `.*`, or otherwise scan from every position of a long line, when the value it wants is in a short last line it could read from a bounded tail?
---
Luau's `string.match(s, "^(.-)([^\n]*)\n?$")` retries the second capture from every position of a line, so it is quadratic in the length of a line: 0.4 s at 10,000 bytes, 40 s at 100,000.

**Why:** c0230 design review 001 F4: the runner's coordinator took the measurer's CPU line off each worker's stdout with that pattern; one failing `toBe` that prints a long value on one line would have stalled every lane's report for minutes, a cost put into the runner's failure path by the issue about cheap tests.

**How to apply:** read the last line from `string.sub(s, -N)` with N above the line's longest form, require a newline (or the start of the text) right before it, and build the rest with one `string.sub`; pin it with a megabyte-line case that is instant when the code is right and a mutant with the whole-output pattern under a short time limit.
