---
id: c0340
type: chore
title: Post merge cleanup
raft: 
depends_on: []
emergent: false
design: draft
created: 2026-09-29
---

# c0340: Post merge cleanup

## Problem
After a PR merges, nothing in the skills says to update the root checkout's `main` or remove the worktree the work was done in. Stale worktrees pile up and the root's `main` lags, so the next raft branches from old code. GitHub now deletes the remote branch on merge, so only local cleanup remains.

## Non-goals
- Automating this in `tracker.sh` (R0020 / c0041 covers worktree tooling).
- Merging: agents still merge only when the human asks.

## Solution
<!-- The approach in one paragraph. -->

## Design
<!-- Modules and paths, public types and signatures, data flow, pure Logic vs adapter split,
     client/server authority. Must agree with the raft's whole-raft design and tracker/architecture.md. -->

### Scalability
### Maintainability
### Usability

### Touched modules
- `.claude/skills/tracker`
- `.claude/skills/execute-raft`
<!-- One backticked repo path per bullet (file or directory prefix), INCLUDING this issue's spec
     paths (e.g. `tests/unit/Maze`). Used for spend attribution
     and for `lune run scripts/affected -- <paths>` to list the affected specs below. -->

### Affected specs
<!-- Output of `lune run scripts/affected -- <touched paths>` plus the new specs. -->

## Unknowns & experiments
<!-- Per unknown: E1 question (pass/fail), how it is tested (experiments/E1-*.luau or a command),
     result if already run during prep, and the fallback design if it fails. -->

## Regression guard
<!-- Existing behavior/specs that must stay green, and new regression specs added here. -->

## Test plan
<!-- Spec file :: case -> AC number. Write these first; they must fail before implementation. -->

## Acceptance criteria

### Checked
AC1: the tracker skill has an "After merge" section: update the root checkout's main, remove the worktree, delete the local branch, and don't delete the remote branch.
AC2: the section handles a root checkout that is on another branch (`git fetch origin main:main`) without switching it.
AC3: execute-raft has a final phase pointing at it.
<!-- ACn: statement. Each maps 1:1 to a `check "ACn: ..."` line in check.sh. Deterministic. -->

### Judged
<!-- Only if genuinely subjective. JCn: statement + rubric (what pass/fail looks like).
     Ruled on by the adversarial code reviewer. -->

### Observed
<!-- Minimal Studio playtest steps for the human (OCn). -->

## Implementation steps
<!-- Ordered, small, each verifiable. -->

## Verification log
<!-- Appended at the end of execution: date, commands run, results. -->
