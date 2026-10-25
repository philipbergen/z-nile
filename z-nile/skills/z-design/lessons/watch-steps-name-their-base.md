---
title: A "stop if these files changed since prep" step names its base and the changes its own dependencies will make
when: design
tags: [rebase, dependencies, execution-window]
check: Does each step that stops on changed files name the base sha it diffs against, and list the hunks this item's own `depends_on` items will bring into those files, with how to merge each?
---
A guard step that stops execution when watched files changed since prep is right to exist when the item's edits are whole-case overrides. But if the item's own dependencies change those very files, the step fires every time, and an executor either escalates for nothing or learns to ignore it, and then misses the real surprise. A base written as `<prep base>` gives nobody a commit to diff against.

**Why:** c0118 design review 006 F4: step 1 watched `main.luau`, the README, zz-rules and the overridden specs, which c0115 (landed), c0116 and c0117 (its dependencies) all change; merging the three implementations conflicted in exactly those files, so the step would always stop.

**How to apply:** name the base as a sha, list each dependency's expected hunks in the watched files with the merge rule for each, and stop only for anything outside the list. Record a run of the item's checks on the current upstream stack.
