# Idea review 003

## Findings

- F1: Two Solution bullets can't be judged true or false as written. The delivery bullet says the worker delivers the raft "using only the installed `zn` program". But the worker is an AI CLI session running the z-work skill, and opening and landing a pull request needs `git` and `gh`. So that bullet is false the moment the delivery runs. The idea also never says where the AI CLI finds the skills it follows (z-work, z-design, zz-review, z-approve). Here those are links under `.claude/skills/`. Meanwhile, the "nowhere else in the host checkout" and "`git status` shows no change" bullets forbid any zn file outside `.tracker/`. A reader can't tell whether linking the skills into omarchy's `.claude/skills/` breaks the idea, or whether using Claude Code with `gh` still counts as "only zn". The idea needs to name the outside tools the delivery may use and say where the skills live.

## Verdict

revise
