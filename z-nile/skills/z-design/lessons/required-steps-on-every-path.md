---
title: A required step sits on every path
when: design
tags: [process, branches]
check: Does every step or refusal that must always happen sit on every path of the process (an approving round, no findings, a single issue, no streams, a plain git commit caught by a command or gate check against the merge base), and does something notice if it was skipped?
---
A step placed inside a branch runs only when that branch is taken. Processes have shortcuts ("approve with no findings, go to Phase 5"), and a required step behind a shortcut is silently skipped in the common case.

**Why:** R0040 design review 4 (F2): stream candidate lessons were written only while answering a code review round, which an approving review skips, and nothing checked for the loss. The fix moved the write to the stream merge, which every stream passes through.

R0040 design review 5 (F2) showed that moving the write to the merge step still missed a path: a blocked or taken-over stream never reaches the merge. What held was to do the work when its input arrives (each report and each stream review), not at any later step.

**How to apply:** for each new step, trace it through every branch of the skill it lives in (especially "go to" shortcuts and blocked or taken-over cases), and prefer doing the work at the moment its input arrives over any later step. If it can still be skipped, add a check that fails when it was.
