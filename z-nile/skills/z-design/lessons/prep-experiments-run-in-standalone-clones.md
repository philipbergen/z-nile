---
title: A prep experiment that commits, resets or moves refs builds its own scratch clone, and takes no target
when: design
tags: [experiments, scratch, refs]
check: Does every script a prep keeps for its experiments (a mutation runner, a prototype applier) that commits, resets, cleans or moves a ref make its own scratch repositories in a fresh `mktemp -d` outside any checkout, with no argument that names where to work (a guard on a given path accepts the real main checkout, which looks like a clone), and does it remove them itself?
---
A scratch *worktree* shares refs with the real repository, so `git update-ref`, a reset or a clean there is not scratch. A guard that inspects a directory it is handed ("is this a standalone clone?") is not enough either: the real main checkout passes the same tests.

**Why:** c0269 design review 002 F2: `experiments/mutants.sh` ran in a "scratch worktree" and its landed-state mutant ran `git update-ref refs/remotes/origin/main HEAD`; the real repository's `origin/main` pointed at a `t@example.invalid` commit for 27 seconds until a fetch restored it. Review 003 F1: the first fix (refuse unless `--git-dir` and `--git-common-dir` are `.git`) accepts `/Users/…/pickman`, the main checkout.

**How to apply:** the script takes no directory. It makes a bare repository of its own (a clone of the real one, its `main` set with `update-ref` inside that clone) and a working clone of that, in `mktemp -d`; it checks the parents are not a checkout, refuses an odd path, removes the directory by a validated path when it ends, and runs through `./zn run --time`. Mutants that move a ref move the scratch clone's.
