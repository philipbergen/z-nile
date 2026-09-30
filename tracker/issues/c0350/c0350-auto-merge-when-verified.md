---
id: c0350
type: chore
title: Auto merge when verified
raft: 
depends_on: []
emergent: false
design: draft
created: 2026-09-29
---

# c0350: Auto merge when verified

## Problem
The skills say "the human merges the PR; agents never merge", so every finished raft waits for a person even when review and tests are all green. The agent should merge its own PR once it has reviewed and run all relevant tests, and engage the human only when something significant is still open after review round 3.

## Non-goals
- Changing `tracker.sh done` to accept a `deferred` answer form (interim: `refuted: below the merge threshold, filed as <id>`).
- Enabling GitHub auto-merge or altering branch protection.

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
AC1: the tracker skill has a "Merging" section that lets the agent merge, requires check.sh --full, CI green on the head sha and a mergeable PR, and forbids `--admin`.
AC2: the tracker skill no longer says agents never merge.
AC3: only a significant leftover after round 3 blocks the merge (both skills say so).
AC4: execute-raft Phase 6 merges without waiting for a human.
AC5: the merge gate is explicit: `CLEAN` merge state, an empty checks list is not green, and code changes after `done` get a new clean review round.
AC6: the interim "below the merge threshold" answer is limited to medium and low findings and points at c0360.
AC7: the final report is written after the merge and carries the merge sha.
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
