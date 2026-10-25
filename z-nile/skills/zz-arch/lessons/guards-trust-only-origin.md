---
title: A guard's allow-list comes from reviewed state
when: design
tags: [security, publish, config]
check: When a guard (publish, a path filter, the jail) is widened by configuration, is that configuration read from origin/main, validated (relative, no `..`, an allowed shape), and never from the working tree a branch can edit?
---
A guard that reads its allow-list from the working tree can be widened by the branch it guards. A tree that edits the config could then push files straight to main without review.

**Why:** R0042 design review 001 F3: letting publish accept project roots read from `projects.toml` would let a branch set a root like `src` or `.` and push arbitrary files to `origin/main`.

**How to apply:** read the config from `origin/main` (the same `read(path)` the publish callback uses), validate each entry's shape, and add spec cases for a root that exists only in the working tree, and for `..` and `.` roots.
