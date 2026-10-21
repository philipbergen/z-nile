---
title: A guard derives what it protects only after it strips the overrides that redirect git
when: both
tags: [guards, git, fence, ordering]
check: Is each value this guard derives from git (the protected repository, the toplevel, a common dir) computed after every inherited override (`GIT_DIR`, `GIT_WORK_TREE`, `GIT_COMMON_DIR`, `GIT_CONFIG_PARAMETERS`, …) is stripped? Is there a case with an inherited `GIT_DIR` that is relative (a hook's `.git`) and one that points at a foreign repository?
---
A guard that asks git which repository it protects, while an inherited `GIT_DIR` is still set, protects whatever that variable names. A relative `GIT_DIR=.git`, which git sets for hooks in a main checkout, resolves against the guard's own folder. From a project home that resolves to no repository at all, so the guard records nothing and lets every ref update through. An absolute one, pointing at another repository, records that one instead.

**Why:** c0120 code review 001 F1: review 002's reorder of `pickman_fence_env` ("refuse before you change anything") moved the `unset GIT_DIR …` below the hooks refusal, and `real=$(git rev-parse --git-common-dir)` went above it. A run from `pickman/` with `GIT_DIR=.git` inherited left `PICKMAN_FENCE_REAL_GIT` empty, and `git update-ref` succeeded in the real repository. No spec caught it: the existing cases set `GIT_DIR` to the same repository, absolute.

**How to apply:** when a guard's steps are reordered, list every read it makes of the repository it protects, and put each one after the full strip. The strip is a change, so it still comes after the read-only refusals (architecture/guard-no-is-explicit). Add the two cases (relative `GIT_DIR` from a subfolder, foreign `GIT_DIR` from the root), each checking that the recorded repository is the checkout's and that the ref guard refuses there. Add a mutant that moves the read above the strip.
