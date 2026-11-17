---
title: An experiment the Implementation steps tell the executor to rerun works where the executor works
when: design
tags: [experiments, executability, mutants]
check: Run as the step says, from the raft's worktree after `./zn ready` (the item under `issues/active/<id>`), does every experiment script the steps name find its specs from its own path, accept the prototype the step tells the executor to make, run bounded by `./zn run --time`, and restore what it changed when that limit stops it?
---
A mutation runner written for the prep's own scratch worktree hard-codes that worktree's name and the backlog path of its specs. Once `ready` moves the item to `active/`, the script refuses the executor's tree or loads nothing, and a run stopped by its time limit leaves a mutant in the source.

**Why:** f0234 design review 001 F3: step 3 told the executor to rerun `experiments/mutants.py` after a hand-merge, but the script asserted its prototype was named `proto-f0234`, read specs from `.tracker/issues/f0234/acceptance/`, and restored only in a `finally` a SIGTERM never reached.

**How to apply:** the script finds its specs beside itself and at the same relative place in the prototype, refuses the main checkout and its own worktree, handles SIGTERM and SIGINT by raising so the restore runs, and the step names the exact commands (make the detached prototype, the bounded run, the removal) and what to do when a mutant's text no longer occurs once. Try each refusal and a stopped run in prep.

**A runner that judges no baseline reads a missing spec as a kill.** R0118's execution (f0145): the runner hard-coded `.tracker/issues/f0145/acceptance`, so on the executor's tree (`issues/active/f0145`) every spec failed to load with "0 passed, 1 failed". That line reads as a kill, and the runner printed the counts and left the verdict to the reader. The runner runs every spec it names unmutated first and stops unless all are green. It computes each row's verdict itself, with a load failure never counted as a kill, and writes no `__pycache__` beside the experiments.
