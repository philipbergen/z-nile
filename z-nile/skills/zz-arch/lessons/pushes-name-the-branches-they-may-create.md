---
title: A push the tooling makes for a person names which branches it may create on origin
when: design
tags: [push, origin, guards]
check: Can this push create a branch on origin that nobody opened a pull request for, or overwrite one that moved there, and does the design name the branches it may push (and never force)?
---
A command that pushes on a person's behalf decides what appears on the shared remote. Pushing whatever branch the checkout is on creates remote branches for prototypes and scratch work, and a forced push overwrites what someone else pushed.

**Why:** c0369 design review 002 F5 and F10: `./zn approve` run inside a prototype pushed that prototype's branch to GitHub and said the approval counted "when its pull request merges", with no pull request; and only a pre-receive refusal tested the failed push, so a forced push passed every case.

**How to apply:** name the branches the command may push (here the prep branch, or a branch already on origin), print what happens to a record on any other, never force, and add a case where origin's branch holds a commit the checkout lacks.
