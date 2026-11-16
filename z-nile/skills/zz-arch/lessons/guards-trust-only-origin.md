---
title: A guard's allow-list comes from reviewed state
when: design
tags: [security, publish, config]
check: When a guard (publish, a path filter, the jail) is widened by configuration, is that configuration read from origin/main, validated (relative, no `..`, an allowed shape), and never from the working tree a branch can edit? And when a step decides or performs a merge (a landing check, `done`, the gate's driver), which checkout's code computes the verdict and does the push, and can the branch being judged edit that code?
---
A guard that reads its allow-list from the working tree can be widened by the branch it guards. A tree that edits the config could then land files on main without review.

**Why:** R0042 design review 001 F3: letting publish accept project roots read from `projects.toml` would let a branch set a root like `src` or `.` and push arbitrary files to `origin/main`.

**How to apply:** read the config from `origin/main` (the same `read(path)` the publish callback uses), validate each entry's shape, and add spec cases for a root that exists only in the working tree, and for `..` and `.` roots.

**Note** (c0252 design review 001 F1): code is configuration too. The dispatcher ran `land-check` and `done` as `{raft worktree}/zn`, so a layer that changed `landcheck.luau` or `done` judged and pushed its own landing with the user's credential, and an honest bug was enough to land a red stack. A merge's judge runs the base's engine (the main checkout's, which only fast-forwards) against the head, with a spec case where the head's copy of the judge says yes and the landing is still refused.
