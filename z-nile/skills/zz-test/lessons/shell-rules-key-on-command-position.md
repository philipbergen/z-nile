---
title: A scanner rule keyed on a shell command checks command position
when: both
tags: [scanners, shell, mutation]
check: Does the rule fire on the command's name inside a quoted argument (`grep -qF "echo" tests/gone.md`, `foo "grep" x`), and which case reports the path next to it?
---
A rule that treats the word `echo` or `grep` as the command marks the next words as text wherever the word stands. A quoted `"echo"` or `"grep"` is a pattern or a message, not a command, so the rule silences a missing path that the scan reported before.

**Why:** c0371 design review 001 F4: the first echo rule marked the argument after any word `echo`, so `grep -qF "echo" tests/gone.md` stopped reporting `tests/gone.md`, which broke the Non-goal that every case reported today stays reported. The grep rule already had the same flaw.

**How to apply:** command position is the first word of a command (after `;`, `&&`, `||`, `|`, `(`, a line start not continued by a backslash), after `then`, `do`, `else`, `if`, `while`, `!`, `{`, `}`, or after `-c`. Give the rule a case where its word is an argument and the next path must still be reported, and a mutant that drops the position test.
