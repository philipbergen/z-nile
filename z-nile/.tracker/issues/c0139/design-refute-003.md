# Refute 003: c0139 (design mode)

- F1: fixed (prototype ad372106): the waiver no longer reads git's wording. One predicate, `conflicts.outsideRepo(top)`, shared with audit's scan: no `.git` entry at the top (a folder or a `gitdir:` file) and no inherited `GIT_DIR`, `GIT_WORK_TREE`, `GIT_COMMON_DIR` or `GIT_INDEX_FILE`. Every other git failure refuses, naming the read.
  - New conflicts.spec case, each with a whole conflict in a working file, each expecting a refusal and no new item: (a) an inherited `GIT_DIR=/nonexistent`; (b) a corrupt `.git/HEAD`, restored after; (c) a linked worktree whose admin folder was removed; (d) a plain copy with no `.git` and `GIT_DIR`/`GIT_WORK_TREE` inherited.
  - The damage is done inside a `bash -c` command run from the sound fixture checkout. The fixture helper refuses a `GIT_DIR` handed down, and checks its folder is a sound repository before running anything.
  - tooling migrate-odd stays green (the must-still-run case).
  - Mutants all killed: W1 (round 002's waiver by message), W2 (inherited variables ignored: through `./zn`, `guardRepoRoot` refuses first, so (d) also calls the guard directly as a script would), W3 (a `.git` file ignored), W4 (never outside).
  - Consequence: a broken checkout stops every writing command until repaired, which is right.
