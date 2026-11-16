---
title: In a rafting prototype stack, each dependent holds its dependency's final tip
when: design
tags: [raft, prototype, stack, dependencies]
from: c0320 (lesson ticket, withdrawn 2026-11-16)
check: For each depends_on edge in the rafting prototype stack, does `git merge-base --is-ancestor <dependency final tip> <dependent prototype>` exit 0?
---
A raft's members are proven together on prototype branches stacked by their `depends_on` edges. A dependent built on an older tip of its dependency does not contain the dependency's final docs and code, so a run on the stack proves a tree the raft will never be.

**Why:** R0099's prototype stack (2026-11-13) had `origin/proto-c0284` built on c0280's older tip 78f5266d while c0280's final tip was 009ea39d. c0280's final docs and code stayed hidden from c0284's prototype until both were merged.

**How to apply:** after the last change to any prototype in the stack, run the `git merge-base --is-ancestor` test for every edge. On a failure, merge or rebase the dependent onto the dependency's final tip and rerun the dependent's specs there (z-design/prototype-includes-the-prepared-dependency says the same of one prep).
