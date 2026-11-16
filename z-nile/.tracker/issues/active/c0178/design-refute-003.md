# Refutes 003: c0178

- F1: fixed, mechanism changed as the review asked: one git template per spec file. The coordinator makes `<template>-<index>/{hooks,info}` for each file and hands it to that file's worker in `GIT_TEMPLATE_DIR`; the worker checks its own folder after its own file. Consequences: `harness :: each spec file of a concurrent run has a git template of its own` (a rendezvous in the nested specs, no timing: a writes and waits for b, b waits for a's write and ends first; killed by "one template for all workers"); the single-file path uses the launcher's folder.
- F2: fixed: `clone.isolated` sets `origin` back to the source asked for; for the repository that is the real one, whose pushes the guard refuses; consequences: `clone-image :: a clone's origin is the source`, asserting the push fails and the image's refs do not change; the old assertion that `origin` was the image now says the source.
- F3: fixed: `pruning.dir()` is the one place; `images.dir()` and the launcher both read it; consequences: the harness case compares them and pins `pruning.run(pruning.dir())` in the launcher; the mutant "prune the project home" is killed.
- F4: fixed: `c0038/deferred` and `c0120/promote-home` take `tooling = true`, like `c0116/promote`; consequences: `overrides :: the specs whose reset or rollback deletes ... carry the tooling` for the three.
- F5: fixed: the AC4 label (check.sh and document), Decisions F7 and the Test plan now describe what is built.
- F6: fixed: the runner-owned names are compared in lower case; both spellings are in the refusal list.
- F7: fixed: `trackerfix.worktrees` fetches origin first, as `./zn worktree` does; the case pushes the branch from `other` and does not fetch in `main`.
- F8: fixed: stacked and orphaned reason comments removed from the thirteen lists.
