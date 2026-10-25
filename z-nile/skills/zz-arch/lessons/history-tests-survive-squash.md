---
title: A "not on main" history test survives main taking the branch as a squash
when: both
tags: [git, squash, history, exemptions]
check: Does any rule decide by "a commit of branch X that main doesn't have"? What does it answer once main lands X, or anything X is built on, as a squash (whose commits never reach main)? Is there a spec case where main squashes the base?
---
A test of the form "this branch holds a commit of X that origin/main doesn't" assumes landing brings X's commits into main. A squash merge lands X's change as one new commit, so X's own commits stay off main for good, and every branch that holds them, including everything built on X, matches the test forever.

**Why:** c0115 design review 013 F1: c0115's freeze ignored any branch holding a commit of `origin/prep-c0115` or `origin/impl-c0115` not on main. Both were built on c0120, which main took as a squash, so the test matched every branch built on c0120: a rogue branch cut from `prep-c0120` that added a skill folder was ignored, and AC12 passed.

**How to apply:** identify a stack by something that stays true after a squash: an exact name, or a commit the stack must hold that is recorded by sha or by a unique subject (a "move commit"). Add a spec case where main takes the base as a squash, with a mutant that brings the history test back.
