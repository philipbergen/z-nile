---
title: A guard's "no" is one explicit answer
when: design
tags: [security, guards, fail-closed]
check: Which outcomes of this guard lookup lead to the unguarded action, and is each of them one explicit "no" answer, with every other outcome (a missing file, a parse error, a missing function, a crash, an unexpected output) treated as "guarded"?
---
A guard lookup that treats "it didn't say yes" as "no" fails open for every failure nobody listed. Patching it case by case (the file is missing, then it doesn't parse, then a function is renamed) never ends, because each new failure is another way to read as "no".

**Why:** R0043 design review 001 F1: after the guards moved into `z-nile/lib/`, the publisher closed only the case where `fence.sh` was missing. A `fence.sh` that failed to source, or a renamed `pickman_guarded`, still read as "no check is running", so the tracker would have published from inside a check run.

**How to apply:** make the unguarded answer a distinct, positive output (a word on stdout with exit 0), act on it only when it is exactly that, and count everything else as guarded. Add spec cases for a broken, a function-less and an other-answer guard, each publishing nothing, and a mutant that goes back to "anything but yes".
