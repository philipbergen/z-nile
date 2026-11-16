---
title: A pid a spec compares is the pid the process records, never a shell's `$!` guess
when: both
tags: [processes, specs, shell]
check: Where a spec backgrounds a process and later kills it or compares its pid, is the backgrounded thing a simple command (`cd "$d"; cmd &`, never `cd "$d" && cmd &`), and is any pid it compares the one the process itself recorded (a db row, a lock file), not `$!`?
---
`a && b &` backgrounds the whole list as a subshell, so `$!` is the subshell's pid, and `kill -- -$!` reaches no process group. A tool started through a shim (rokit's `lune`) runs the real tool as the shim's child, so even a correct `$!` is not the pid the tool reports as its own.

**Why:** c0165 prep (2026-10-26).
- The killed-owner and wait-timeout cases of gate.spec used `cd "$1" && … perl -e 'setpgrp…' lune … &`. The kill missed, and the "killed" owner finished and recorded a pass.
- Once fixed, the timeout case still failed under `./zn check` (rokit's lune 0.10.5). Its message named the shim's child, not `$!`.

**How to apply:** background a simple command after `;`, start it in its own process group (`perl -e 'setpgrp(0,0); exec @ARGV'`), and kill the group. Compare pids against what the process wrote down (its db row, its lock record).
