## zz-test/specs-never-burn-real-resources
```
title: A promoted spec never burns CPU, waits for a real limit or starts a spinner
when: design
tags: [specs, cpu, stand-ins, check-sh, promotion]
check: Does any file under acceptance/ with a .spec.luau name spin, sleep, or wait for a real limit to fire; and for each such proof, is it a check.sh-only script (no .spec.luau name) that runs only while the sequestered folder exists, bounded by a kernel cap (ulimit -t) and a CPU bound inside each spinner, with the suite keeping the same rules through a stand-in (a recording ulimit, a clock/CPU meter the code under test reads, a stub entry) plus one unmocked cheap observation (the limit is in force) that kills the "set in a subshell" mutant?
```
Acceptance specs are promoted into the permanent suite and run on every full gate, on the user's machine. c0191 round 1 to 5 shipped specs that ran perl spinners to prove a CPU limit; the user: "You can use it to prove that your implementation works and then it gets removed. I'm not running that."

Why: the real-limit proof is worth running once, but a spec runs forever. Moving it out of the suite loses the guard unless the suite watches what the limit asks for (stand-ins) and that it reaches the process (a limit below the jail's, read with `ulimit -t`, no CPU). Review 007 showed that the stand-in alone passes the mutant "set the limit in a subshell", and that a wall-clock stand-in passes a runner that never signals unless it asserts the elapsed time.

How to apply: a stand-in clock for `time`/`times` (perl driver with CORE::GLOBAL overrides, empty prototypes), assert elapsed under a loose bound; a proof script in acceptance/ with no .spec.luau name, gated in check.sh on the sequestered path, with `ulimit -t 60` in front.

## z-design/contradicting-results-are-unknowns
```
title: An experiment that contradicts a recorded finding is a new unknown, not a test input to change
when: design
tags: [experiments, unknowns]
check: Did any experiment in this round behave differently from what an E-n entry claims (a spinner the CPU limit did not stop), and is that difference recorded with its own experiment, a stated gap and a fallback, rather than worked around by changing the input?
```
c0191 round 008: E17's first self-bounded spinner (`times` in a loop) was not stopped by `ulimit -t 1`; the prep switched the spinner to `alarm 20; 1 while 1` and recorded only that, while E1 still said the limit works. A syscall-heavy loop escapes `ulimit -t` on macOS (7.7 CPU s on a 1 s limit), which matters for the engine and hook entry, whose only bound is CPU.

## Note: the open question for the user
Whether the promoted proof files (`proof-bounded.luau`, `proof-limits.luau`) must be deleted after `./zn done` (the user said the proof "gets removed"), or may stay inert as evidence.
