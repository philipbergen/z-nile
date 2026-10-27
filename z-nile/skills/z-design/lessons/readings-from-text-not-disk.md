---
title: A value's meaning comes from its text, never from what exists on disk
when: design
tags: [conventions, paths, determinism]
check: Does any reading depend on the filesystem? What does it say before and after this item's own work creates the thing, and in a fresh clone (no untracked or ignored files)?
---
A rule that guesses what a value means from what exists (is there a folder by that name in the home, at the top?) changes its answer when the item's own work creates the thing, and differs between the main checkout (untracked `build/`, ignored files), a fresh worktree, CI and a trial merge.

**Why:** c0141 design review 002 F1: check-paths read a Touched entry home-relative or root-relative by which folder existed, so an item creating `pickman/.github/workflows/new.yml` had its correct check reported and its wrong one exempt until the folder existed, then the two swapped; c0117's `.models.toml` would flip the day c0117 creates it.

**How to apply:** take the convention from the text (here the whole document: any `<home>/` entry means from the top), add a case that runs before and after the item's path exists with the same verdict, and a mutant where existence decides.
