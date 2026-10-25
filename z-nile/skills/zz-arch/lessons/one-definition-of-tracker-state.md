---
title: One definition of what a guard lets through, shared by every guard
when: design
tags: [security, guards, git]
check: Does every guard that lets "tracker-only" (or any allow-listed) changes through call the same function, and does that function read git's raw diff (`diff-tree -r --raw --no-renames`: both sides of a rename, every file mode) rather than `--name-only`, and match whole folders (`<root>/`) rather than string prefixes?
---
When several guards each decide "is this change only tracker state", each spelling of the test is a new place to be wrong: `git diff --name-only` hides a rename's source (a deletion of code that passes), a prefix without its slash admits a sibling (`z-nile/nextgen/`), and names alone miss a symlink or a submodule under an allowed folder. Write the test once, from git's raw diff with renames off, checking modes and whole path components, and have every guard (the wrapper, the broker, the tripwire, the watermark) call it.

**Why:** c0117 design review 002 F1: the broker deleted `src/guard.lua` from `main` through a `git mv` into a tracker root, and pushed `z-nile/nextgen/evil.luau`; the wrapper, the broker and the tripwire each had their own copy of the test. F2: the same allow-list let a step weaken its own `check.sh` on `main`.

**How to apply:** one module (`trackerstate.luau`); spec cases for a rename out of a root, a sibling of an allowed path, a symlink, a submodule, git's own config files, and a sequestered file changed versus moved; a mutant per rule.
