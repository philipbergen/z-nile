---
title: An experiment that contradicts a recorded finding is a new unknown, not a test input to change
when: design
tags: [experiments, unknowns]
check: Did any experiment in this round behave differently from what an E-n entry claims (a spinner the CPU limit did not stop), and is that difference recorded with its own experiment, a stated gap and a fallback, rather than worked around by changing the input? And when a check went red once and did not reproduce, was its output kept, and does the executor's step say what to do if it comes back (rerun once keeping the output, then stop and name the case)?
---
c0191 round 008: E17's first self-bounded spinner (`times` in a loop) was not stopped by `ulimit -t 1`; the prep switched the spinner to `alarm 20; 1 while 1` and recorded only that, while E1 still said the limit works. A syscall-heavy loop escapes `ulimit -t` on macOS (7.7 CPU s on a 1 s limit), which matters for the engine and hook entry, whose only bound is CPU.

**Note** (c0392 design review 001 F4): during prep, c0210's `manifest.spec` went red in one `./zn check c0210` run. The output was not kept, and three reruns were green. The design wrote "not explained" and gave the executor no rule. Keep the output of any red you cannot reproduce, and give the Implementation step a rerun-once-then-escalate fallback.
