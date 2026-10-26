---
title: A "stop if these files changed since prep" step names its base and the changes its own dependencies will make
when: design
tags: [rebase, dependencies, execution-window]
check: Does each step that stops on changed files name its base sha, check that every watched path (written from the checkout's top) exists on origin/main, and allow exactly the dependencies' changes, as listed hunks with a merge rule each when the dependencies are landed and change the files a little, or as their landing commits plus conflicts only in this item's own hunks when they rewrite the files or are still in review?
---
A guard step that stops execution when watched files changed since prep is right to exist when the item's edits are whole-case overrides. But if the item's own dependencies change those very files, the step fires every time, and an executor either escalates for nothing or learns to ignore it, and then misses the real surprise. A base written as `<prep base>` gives nobody a commit to diff against.

**Why:** c0118 design review 006 F4: step 1 watched `main.luau`, the README, zz-rules and the overridden specs, which c0115 (landed), c0116 and c0117 (its dependencies) all change; merging the three implementations conflicted in exactly those files, so the step would always stop.

**How to apply:** name the base as a sha and write every watched path from the checkout's top, checked to exist on `origin/main`. When the dependencies are landed and touch the watched files a little, list each expected hunk with its merge rule and stop for anything else. When a dependency rewrites the files or is still in review, allow its landing commits (its PR's squash) and tracker-only commits, allow merge conflicts only in this item's own hunks, and require the item's checks and the full gate after the merge. Either way, record a run of the item's checks on the current upstream stack.

c0118 design review 007 F1, the same step a second time: its expected-hunk list covered one block of `main.luau` while c0116, still in review, rewrites about 1,200 lines there and the README, and one watched path was written from the wrong folder, so its watch was silently empty. When a dependency rewrites the watched files wholesale and is not yet landed, list its landing commits (its PR's squash), not its hunks; allow conflicts only in the item's own hunks; write every watched path from the checkout's top and check it exists on `origin/main`.

c0121 design review 003 F2: a step copied from another item's (c0118's) stopped every time for its own reasons: it required the checks to pass right after the merge (before the implementation steps), it named no branch the raft runs on, and it allowed a landing by a PR number the dependency might never land under. Name the branch, put the passing point after the steps that build what the checks need, and identify a dependency's landing by content (the done raft holding it, the first-parent commit on main whose subject starts `R<id>:`).
