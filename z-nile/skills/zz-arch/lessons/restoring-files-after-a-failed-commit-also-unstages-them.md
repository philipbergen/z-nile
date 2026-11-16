---
title: A command that restores files after a failed git commit also unstages them
when: both
tags: [git, failure-path, index]
check: After each failure path of a command that stages and commits, is `git status --porcelain` empty, and does the advice in its message work from that state?
---
Putting the working files back is half of "nothing was recorded": the `git add` before the failed commit is still in the index. A restore without an unstage leaves a staged add of a file that is no longer there, and the next command (a sync, a re-run, a worktree removal) trips on it.

**Why:** c0348 design review 001 F2: its prototype restored the planned files when the local commit failed after a successful publish. The status was `AD`, `./zn sync` then left the file deleted, the re-run it advised was refused with the same advice, and Phase 6's `git worktree remove` would have refused the dirty tree.

**How to apply:** on every path after a `git add`, unstage the paths (`git reset -q -- <paths>`) before restoring them; when the unstage can fail too, the message names the command to run by hand. Pin it with a case that asserts an empty status and then follows the message's own advice.
