---
title: A merge commit is grepped for conflict markers across the whole tree
when: build
tags: [merge, conflicts, landing]
check: Before committing a merge, did `git grep -n -E '^(<<<<<<<|=======$|>>>>>>>)'` over the whole tree (not only the files you resolved) come back empty?
---
`./zn sync` can stop on one conflict and leave others in files it reports less loudly; resolving the file you saw and then `git add -A` commits markers in the rest. Text files such as `architecture.md` pass the gate with markers in them, because its parsers skip lines that are not rows or edges.

**Why:** f0110's prep takeover, 2026-10-26: the merge of main reported a conflict in a z-design lesson; that one was resolved, `git add -A` committed `pickman/.tracker/architecture.md` with two marker blocks (the Touch and View rows, and the deps block), and #154 put them on main, where every later merge touching the file tripped on them.

**How to apply:** after resolving, run `git diff --name-only --diff-filter=U` (must be empty) and the whole-tree marker grep before `git commit`; never `git add -A` a merge you have not grepped.
