---
title: A reader of shell text states what it does with what bash carries across lines
when: both
tags: [scanners, shell, state]
check: What does the reader do on line 2 of a `bash -c '…'` script whose line 1 is `cd "$ZN_ROOT"`, after the closing paren of `(cd … && …)`, and after a `)` or `(` inside quotes, and does the spec pin each of those with a case that reports a missing path?
---
A per-line scanner of a check.sh sees `cd`, an open quote or a subshell on one line and what they change on the next. A rule that stops at the end of the line reads later lines of a multi-line `bash -c` script from the wrong folder, so a missing path goes unreported (a false pass, not a false report).

**Why:** c0371 design review 001 F2: the first root-cd rule ended with the line, while c0292 AC7 and several raft checks put the `cd "$ZN_ROOT"` on line 1 of a script and their paths on later lines. The live tree passed only because no later line held a path. The probe found six missed reports: line 2 of a script, a top-level cd, `)` and `(` inside quotes, a literal cd after the root cd, and the script's closing quote.

**How to apply:** keep the quoting of the whole text (single-quoted scripts as contexts of their own, double quotes, backslash), carry the state until the group or script that holds it closes, count parentheses only outside quotes (and a `$(` inside double quotes), and write one reporting case per way it can end.
