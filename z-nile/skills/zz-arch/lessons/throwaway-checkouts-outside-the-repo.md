---
title: A throwaway checkout a tool builds lives outside the repository, as its own repository
when: design
tags: [fence, worktrees, temp-files]
check: Does this command register a worktree or write under a checkout's .cache, and would fence.snapshot of any checkout see it? Does the throwaway copy still have the history and objects the commands run in it need?
---
The fence of every spec run records the worktrees registered under its checkout's `.cache` and fails the run when that set changes. A tool that builds a throwaway worktree there trips the tripwire of any spec run that overlaps it, and AGENTS.md tells every agent to stop on that alarm.

**Why:** c0152 design review 002 F1: merge-check's trial worktree `.cache/merge-check-<sha>` made three overlapping spec runs report "worktrees registered under .cache … Stop and report this", while merge-check itself said ok.

**How to apply:** use a fresh `mktemp -d` under `$TMPDIR` (as remap does) and make it its own repository. A `git clone --shared` with its origin removed keeps the history (a `git archive` + `git init` copy failed the specs that read history). Never teach the fence to ignore the tool's name. A copy that can't be removed is a failure naming it.
