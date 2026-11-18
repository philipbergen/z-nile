---
title: Probe a new agent CLI inside a throwaway git repository with the dispatcher's PATH
when: design
tags: [cli, probes, repository-safety]
check: Was the new CLI probed inside a throwaway git repository under `.cache`, with the dispatcher's PATH (the git and gh wrappers) and its shell, and does anything it writes land in a repository's `.git`, in its common directory or outside the worktree?
---
The dispatcher runs a CLI inside an item's worktree, whose `.git` is a link to the shared repository's common directory. A CLI that snapshots or indexes the repository may write there and run git through the wrappers in ways a scratch-folder probe never shows.

**Why:** c0175 design review 001 F6 (2026-11-15). opencode writes `.git/opencode` into the repository's common git directory, snapshots the worktree with `git -c …` calls that go through the git wrapper, and its tool shell is zsh. No probe had run inside a git repository.

**How to apply:** make a throwaway repository with a worktree under `.cache`, put `z-nile/bin` first on PATH, run the CLI's tiniest prompt there, and list every file it wrote. Turn off whatever writes into `.git`, or name it as a high risk.
