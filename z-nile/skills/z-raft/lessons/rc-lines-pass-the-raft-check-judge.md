---
title: A raft's RCn lines pass raftcheck.judge
when: design
tags: [raft, rc, check-sh, grammar]
check: Has `raftcheck.judge` (against the raft template rendered for this raft and project) accepted the check.sh after the last edit to an RCn line, with no backslash, `$(` or `${` outside a single-quoted command?
---
The rafting gate reads a raft's `check.sh` as the rendered template's RC0 lines, then only `check "RCn: …"` lines and `finish`. A label with `\"` inside it runs fine in bash, but the judge refuses it with `\ in a check's words`.

**Why:** R0117 design review 001 F3. RC2's label quoted the captured outcome as `\"Enter or A plays\"`.

**How to apply:** write labels in plain words. Put any quoting or `$(…)` inside the single-quoted `bash -c` body. After each edit to an RCn line, run `raftcheck.judge` from a scratch Lune script under `.cache/` through `./zn run`, with `raftcheck.render(template, { ID = <R-id>, PROJECT = <project> })` as the second argument.
