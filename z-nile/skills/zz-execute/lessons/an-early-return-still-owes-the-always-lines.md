---
title: An early return a fix adds still owes what the command prints on every path
when: build
tags: [review, fix, cli]
check: For each early return a fix adds to a command, which lines does the Design or a captured outcome say the command prints "always" or "on every path", and does the new return still print them?
---
A refusal added at the top of a command is reviewed for what it refuses. What the paths below it used to print on every exit is easy to lose.

**Why:** R0138's code reviews 3 and 4 added two refusals at the top of `./zn watch-kick` (a short CPU limit; a dispatched step). The "watch-net: no pass since" line, which d0383's Design and its third captured outcome owe on every kick, was printed only at the bottom, so a refused kick lost it. Five code reviews passed it; the final review found it by reading the outcome against the code (final-review-001 F1, 2026-11-20).

**How to apply:** Put the always-owed output in one local function and call it before every return, or structure the command so every exit passes one tail. Add a case that takes the new early path and asserts the owed line.
