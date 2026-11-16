---
title: An experiment that contradicts a recorded finding is a new unknown, not a test input to change
when: design
tags: [experiments, unknowns]
check: Did any experiment in this round behave differently from what an E-n entry claims (a spinner the CPU limit did not stop), and is that difference recorded with its own experiment, a stated gap and a fallback, rather than worked around by changing the input?
---
c0191 round 008: E17's first self-bounded spinner (`times` in a loop) was not stopped by `ulimit -t 1`; the prep switched the spinner to `alarm 20; 1 while 1` and recorded only that, while E1 still said the limit works. A syscall-heavy loop escapes `ulimit -t` on macOS (7.7 CPU s on a 1 s limit), which matters for the engine and hook entry, whose only bound is CPU.
