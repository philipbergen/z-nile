---
title: A fixture's local git remote uses an absolute URL
when: both
tags: [fixtures, git, worktrees]
check: Does every local remote a fixture sets up use an absolute path, so a push from a linked worktree reaches it?
from: f0428 design experiment E7 (2026-11-21)
---
A relative remote URL resolves against the current folder. From a linked worktree it points somewhere else, and the push goes nowhere without an error that fails the case.

**Why:** f0428 design, experiment E7 (2026-11-21).

**How to apply:** build the URL from the fixture's absolute path, and assert after the push that the remote holds the commit.
