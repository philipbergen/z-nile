---
title: A reviewer whose inputs must be limited starts outside every directory that has agent-instruction files
when: design
tags: [review, limited-view, isolation]
check: Does any reviewer that must see only a limited view start in a folder with a CLAUDE.md or AGENTS.md above it (the CLI loads those from the working directory's parents before any prompt is read), and what did a real run of each runtime in its role chain load?
---
A view folder inside a checkout inherits the checkout's instruction files, and those tell the reviewer to read skills and search lessons: the very trail the view was built to keep out.

**Why:** c0262 design review 001 F5: the view lived at `<worktree>/.cache/final/<id>`, so the dispatched reviewer's context already held the worktree's CLAUDE.md, AGENTS.md and project memory.

**How to apply:** put the view under a root outside every checkout (an environment variable for specs), pin the logged working directory in a dispatch spec, and run one real session per runtime in the role's chain to see what it loads.
