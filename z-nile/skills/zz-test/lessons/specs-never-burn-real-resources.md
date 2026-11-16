---
title: A promoted spec never burns CPU, waits for a real limit or starts a spinner
when: design
tags: [specs, cpu, stand-ins, check-sh, promotion]
check: Does any file under acceptance/ with a .spec.luau name spin, sleep, or wait for a real limit to fire; and for each such proof, is it a check.sh-only script (no .spec.luau name) that runs only while the sequestered folder exists, bounded by a kernel cap (ulimit -t) and a CPU bound inside each spinner, with the suite keeping the same rules through a stand-in (a recording ulimit, a clock/CPU meter the code under test reads, a stub entry) plus one unmocked cheap observation (the limit is in force) that kills the "set in a subshell" mutant?
---
Acceptance specs are promoted into the permanent suite and run on every full gate, on the user's machine. c0191 round 1 to 5 shipped specs that ran perl spinners to prove a CPU limit; the user: "You can use it to prove that your implementation works and then it gets removed. I'm not running that."

**Why:** the real-limit proof is worth running once, but a spec runs forever. Moving it out of the suite loses the guard unless the suite watches what the limit asks for (stand-ins) and that it reaches the process (a limit below the jail's, read with `ulimit -t`, no CPU). Review 007 showed that the stand-in alone passes the mutant "set the limit in a subshell", and that a wall-clock stand-in passes a runner that never signals unless it asserts the elapsed time.

**How to apply:** a stand-in clock for `time`/`times` (perl driver with CORE::GLOBAL overrides, empty prototypes), assert elapsed under a loose bound; a proof script in acceptance/ with no .spec.luau name, gated in check.sh on the sequestered path, with `ulimit -t 60` in front.

**Note (c0230, user 2026-11-01):** the rule is wider than CPU: a test runs on a shared machine at every gate, forever, so it is fast and cheap. It burns no CPU, sleeps no seconds and writes no thousands of files. The user: "You can use it to prove that your implementation works and then it gets removed. I'm not running that. Make a lesson, fast tests are important". c0191's rounds 1 to 5 shipped perl spinners that burned a core on every full gate. Ask of a spec: does it burn CPU, wait, or write many files, and if so is that proof a one-time `check.sh`-only script outside the promoted suite? c0178's `fixtures: N files written, M processes started` line is the cost signal for files and processes; the suite keeps the rule through a stand-in plus one cheap unmocked observation.
