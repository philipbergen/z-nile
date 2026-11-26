---
title: A git confinement check names the repository git resolves
when: both
tags: [security, git, confinement]
check: Does the confinement check compare the repository git resolves (top level, git dir, common dir) with the allowed root, not just the folder passed with -C, with GIT_CEILING_DIRECTORIES stopping upward discovery and nothing created before the checks pass?
from: f0428 review 001 F1 and review 002 N1 (2026-11-21)
---
`git -C <dir>` finds a repository by walking up from `<dir>`, so a folder inside the allowed root can resolve to a repository outside it, and a linked worktree's git dir and common dir can sit elsewhere.

**Why:** f0428 review 001 F1 and review 002 N1 (2026-11-21): the host helper wrote refs into a repository outside its allowed root.

**How to apply:** set `GIT_CEILING_DIRECTORIES`, read `rev-parse --show-toplevel`, `--git-dir` and `--git-common-dir`, and require all three inside the root before any write. Create nothing (folders, refs, worktrees) before the checks pass. Add a case with a folder in the root that resolves to a repository outside it.
