---
title: Remove a capture worktree only after land says it landed
when: build
tags: [land, worktrees, capture]
check: Did `./zn land` print `landed <sha> on main` (read whole, with its exit code unmasked by a pipe), before the spend was recorded and the worktree and branch were removed?
---
`./zn land` can fail after its full gate (it gives up when it loses the race to `main` three times), and the capture's sections then exist only on its branch.

**Why:** f0126's prep (2026-10-25) captured c0150 with `./zn land 2>&1 | tail -3` in the background: the pipe's exit code was `tail`'s, so a "lost the race to main 3 times" failure looked like success, and the worktree and branch were removed. The commit survived only as a dangling object and had to be cherry-picked into a new capture worktree and landed again. f0158's prep (2026-10-26) captured c0159 with `./zn land 2>&1 | tail -1; …; git worktree remove … && git branch -D …` in one command: the land lost the race three times and the chained cleanup still removed the worktree and the unlanded branch, so the filled text was lost and had to be rewritten.

**How to apply:** run `land` without a pipe (or with `set -o pipefail`), look for its `landed <sha> on main` line, and only then run `./zn spend` and the removal command it prints. On a lost race, run `land` again in the same worktree.
