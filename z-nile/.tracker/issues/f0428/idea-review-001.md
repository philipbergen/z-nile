# Idea review 001

## Findings

- F1: Solution sentences 1 and 2 contradict each other, so no reader can find both true at once. Git's status lists an untracked nested repository as `?? .tracker/`. Hiding it needs an ignore rule in `.gitignore`, `.git/info/exclude` or `core.excludesFile`, and each of those is an ignore file. So either the status reports `.tracker` (sentence 2 fails), or zn writes an ignore rule (sentence 2 fails again). The one way out is a rule the owner set up beforehand, which the idea never states. The same applies to the host's `.worktree/` worktrees and any `.cache/` output. The idea needs to say where `.tracker` lives, or which ignore file zn may write and whether that write counts as a change.

## Verdict

revise
