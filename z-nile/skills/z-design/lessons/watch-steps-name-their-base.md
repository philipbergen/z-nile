---
title: A "stop if these files changed since prep" step names its base and the changes its own dependencies will make
when: design
tags: [rebase, dependencies, execution-window]
check: Does each step that stops on changed files name the base sha it diffs against, and list the hunks this item's own `depends_on` items will bring into those files, with how to merge each?
---
A guard step that stops execution when watched files changed since prep is right to exist when the item's edits are whole-case overrides. But if the item's own dependencies change those very files, the step fires every time, and an executor either escalates for nothing or learns to ignore it, and then misses the real surprise. A base written as `<prep base>` gives nobody a commit to diff against.

**Why:** c0118 design review 006 F4: step 1 watched `main.luau`, the README, zz-rules and the overridden specs, which c0115 (landed), c0116 and c0117 (its dependencies) all change; merging the three implementations conflicted in exactly those files, so the step would always stop.

**How to apply:** name the base as a sha, list each dependency's expected hunks in the watched files with the merge rule for each, and stop only for anything outside the list. Record a run of the item's checks on the current upstream stack.

c0118 design review 007 F1, the same step a second time: its expected-hunk list covered one block of `main.luau` while c0116, still in review, rewrites about 1,200 lines there and the README, and one watched path was written from the wrong folder, so its watch was silently empty. When a dependency rewrites the watched files wholesale and is not yet landed, list its landing commits (its PR's squash), not its hunks; allow conflicts only in the item's own hunks; write every watched path from the checkout's top and check it exists on `origin/main`.
