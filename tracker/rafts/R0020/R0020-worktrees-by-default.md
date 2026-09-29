---
id: R0020
type: chore
title: Worktrees by default
single: true
issues: [c0040]
design: reviewed
created: 2026-09-28
---

# R0020: Worktrees by default

## Theme
A single-issue placeholder raft for c0040. Every raft runs in its own raft-named worktree, so the main checkout stays on `main` for capture and prep, and several rafts can run side by side.

## Whole-raft design
See c0040's Design. The only interface is the CLI surface:
- `tracker.sh worktree <R>` prints an absolute path;
- `tracker.sh worktree-prune`;
- `start` accepts an existing raft branch.

## Order & dependencies
One issue. It is independent of R0010 (in flight); the two touch different code. Expected overlap on merge:
- `SETUP.md`: both add paragraphs;
- `.claude/skills/tracker/SKILL.md`: R0010 doesn't change it.

Whoever merges second rebases and re-runs their gate.

## Experiments phase
c0040's E1 and E2 were run in prep and PASSED. E3 (the main worktree is listed first) is pinned by the spec case "works from inside another worktree".

## Exit criteria
- **RC0**: the full gate, `c0040/check.sh` and `promote-check`, as generated.
- No extra RC: c0040's spec is itself end to end.

## Risks & rollback
- **Risk**: a worktree under `.worktrees/` is committed from a branch created before `.gitignore` had the entry. Mitigation: `worktree` always branches from `origin/main`, which has the entry once this merges. The R0010 branch predates it, so don't create worktrees inside the main checkout until R0010 is done.
- **Rollback**: revert the PR. `start` remains backward compatible.

## Addressed during execution
