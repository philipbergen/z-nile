---
title: A prep experiment that commits, resets or moves refs builds its own scratch clone, and takes no target
when: design
tags: [experiments, scratch, refs]
check: Does every script a prep keeps for its experiments (a mutation runner, a prototype applier) that commits, resets, cleans or moves a ref make its own scratch repositories in a fresh `mktemp -d` outside any checkout, with no argument that names where to work (a guard on a given path accepts the real main checkout, which looks like a clone), and does it remove them itself And does every experiment script the prep keeps `cd` into its own fixture under `.cache/` before it writes anything, with no relative write and no `/tmp` output, and does its record name the bounded command it ran under? And does a long run's output go to a file named for the issue (`<scratchpad>/<id>-…/`), never a generic name, since every agent of one session shares the scratchpad?
---
A scratch *worktree* shares refs with the real repository, so `git update-ref`, a reset or a clean there is not scratch. A guard that inspects a directory it is handed ("is this a standalone clone?") is not enough either: the real main checkout passes the same tests.

**Why:** c0269 design review 002 F2: `experiments/mutants.sh` ran in a "scratch worktree" and its landed-state mutant ran `git update-ref refs/remotes/origin/main HEAD`; the real repository's `origin/main` pointed at a `t@example.invalid` commit for 27 seconds until a fetch restored it. Review 003 F1: the first fix (refuse unless `--git-dir` and `--git-common-dir` are `.git`) accepts `/Users/…/pickman`, the main checkout.

**How to apply:** the script takes no directory. It makes a bare repository of its own (a clone of the real one, its `main` set with `update-ref` inside that clone) and a working clone of that, in `mktemp -d`; it checks the parents are not a checkout, refuses an odd path, removes the directory by a validated path when it ends, and runs through `./zn run --time`. Mutants that move a ref move the scratch clone's.

c0273 design review 001 F6: `E1-rojo-jsonc.sh` began with `rm -rf h1 …; mkdir -p …` relative to wherever it was started and wrote builds to `/tmp`; it now `cd`s into `<checkout>/.cache/c0273-probe/e1` first. The mutation runner restores files from the text it read instead of running `git checkout` in the prototype worktree.

f0206 prep: a mutant tried by hand in the scratch prototype worktree was undone with `git checkout --` on a file added with `git add -N`, which emptied it (an intent-to-add entry has an empty blob), and its backup, written to a path relative to the home (`../../../`), landed in the main checkout's root. Undo a hand-run mutant from the text read before the edit (or the prototype patch), and keep any copy in the session's scratchpad, never a relative path.

c0369 re-prep (2026-11-16): the mutation runner's output was redirected to `<scratchpad>/mutants.log`; another agent of the same session wrote its own `mutants.log` there meanwhile, both runs truncated the one file, and the first run's results were lost and rerun. A run's log goes in a folder named for the issue (`<scratchpad>/c0369-mut/run.log`).
