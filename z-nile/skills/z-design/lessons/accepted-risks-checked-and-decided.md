---
title: An accepted risk states checkable premises, and a weakened guard is the user's call
when: design
tags: [risks, guards, scope]
check: Does each accepted risk's premise hold against the repo (supported hosts in `SETUP.md`, which guards run where, the skills), and does a risk that weakens a guard (a new way past the lock, the jail, a fence) carry a `Decided with the user` line instead of the author's acceptance?
---
A risk accepted in a raft's Risks reads as settled, so its premise is never rechecked, and a guard can lose ground without anyone deciding it.

**Why:** R0047 design reviews 002 F2 and 003 F1: the time-based reuse rule let a forward clock step on Linux take a live run's lock, and the author accepted it on "Linux runs are CI only", which `SETUP.md` contradicts; the old rule could never do that. The user then chose a design without the risk (start ids compared for equality).

**How to apply:** write each premise as something a reviewer can check, check it, and put any risk that weakens a guard to the user with the options and what each costs.
