---
id: c0360
type: chore
title: Done deferred answer
raft: 
depends_on: []
emergent: false
design: draft
created: 2026-09-29
---

# c0360: Done deferred answer

## Problem
`tracker.sh done` accepts an answer to a review finding only as `- F<n>: fixed ...` or `- F<n>: refuted ...`, and checks nothing else. With agents now merging on their own (c0350), a medium or low finding left after review round 3 has to be answered as `refuted: below the merge threshold, filed as <id>`, which is dishonest and lets a high finding through just as easily. Add a `- F<n>: deferred <id>: <why>` form that `reviewProblem` accepts only when the finding's severity is medium or low and `<id>` is an existing backlog issue.

## Non-goals
- Changing what counts as significant (unresolved high or failed Judged criterion).

## Solution
<!-- The approach in one paragraph. -->

## Design
<!-- Modules and paths, public types and signatures, data flow, pure Logic vs adapter split,
     client/server authority. Must agree with the raft's whole-raft design and tracker/architecture.md. -->

### Scalability
### Maintainability
### Usability

### Touched modules
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
