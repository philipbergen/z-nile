---
id: R0020
type: chore
title: Worktrees by default
single: true
issues: [c0041]
design: reviewed
created: 2026-09-28
---

# R0020: Worktrees by default

## Theme
A single-issue placeholder raft for c0041. It establishes **the worktree rule** (user decision, 2026-09-30): the main checkout stays on `main` and is never edited; every change (raft execution, issue capture, ticket-prep, skill and doc edits) is made in its own git worktree, lands by pull request, is merged by the agent under the tracker skill's merge conditions, and is then pulled into the main checkout. Several rafts and captures can then run side by side, and the human's checkout is always current and clean.

## Whole-raft design
See c0041's Design. The interfaces are:
- the CLI: `tracker.sh worktree <R-id | name>` prints an absolute path; `tracker.sh worktree-prune`; `start` accepts an existing raft branch and opens a draft PR only for GitHub origins;
- the hooks read the tree from their input;
- the documents: one worktree rule and one landing procedure (tracker skill), referenced by the other skills, the prompt template, AGENTS.md and SETUP.md.

There is no new dependency edge (`tracker/architecture.md` is unchanged).

## Order & dependencies
One issue, no dependencies. R0010 (the former in-flight raft that conflicted with it) has merged.
- **Bootstrap: how R0020 itself is executed.** `tracker.sh worktree` doesn't exist until this raft merges, and the prompt inlines today's execute-raft ("switch to main, start"). So the human creates the worktree by hand and launches the agent in it: `git -C <root> worktree add -b R0020-worktrees-by-default ../pickman-R0020 origin/main`, then `cd ../pickman-R0020 && claude`. The executor runs `scripts/tracker.sh start R0020` there. `start` finds the branch already current (today's `start` would also work), so it never switches branches, and the main checkout is untouched. Do not create `.worktrees/` by hand in the main checkout before this raft has merged: it isn't gitignored yet.
- Expected merge overlap with other in-flight rafts: the skills (`tracker`, `execute-raft`, `make-prompt`, `review`), `tracker/templates/prompt.md` and `SETUP.md`. R0070 (review second order, in flight) may touch the review and metrics skills; whoever merges second rebases and re-runs their gate.

## Experiments phase
c0041's E1, E2, E5 and E6 were run in prep and PASSED. E6 ran a throwaway prototype of the tooling against the sequestered spec, with four planted mistakes each caught. E3 is pinned by the spec case "works from inside another worktree", and E4 (whether the Stop hook's `cwd` follows a `cd`) is optional because nothing depends on it.

## Exit criteria
- **RC0**: the full gate, `c0041/check.sh` and `promote-check`, as generated.
- No extra RC: c0041's spec is itself end to end, and its AC5 and JC1 pin the documents.

## Risks & rollback
- **Risk: process weight.** Every capture and prep now costs a PR and a CI run. Accepted by the user; the landing procedure is one documented sequence, and merging is the agent's job.
- **Risk: an agent forgets the rule.** It's a documented rule, not a guard. Mitigation: the prompt's first action and the launch line put the agent in the worktree from the start. A mechanical guard is a candidate follow-up (c0041 Non-goals).
- **Risk: a worktree under `.worktrees/` is committed from a branch created before `.gitignore` had the entry.** `worktree` branches from `origin/main`, which has the entry once this merges, and the fixtures used by the spec carry it.
- **Risk: two unmerged worktrees pick the same issue number.** The existing `tracker.sh renumber` on rebase covers it (tracker skill, "Conflicts").
- **Rollback**: revert the PR. `start` remains backward compatible, and the old "commit to main" text returns with the revert.

## Addressed during execution
