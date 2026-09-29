---
id: f0160
type: feature
title: Power pellets
raft: 
depends_on: [f0150, f0170]
emergent: false
design: draft
created: 2026-09-28
---

# f0160: Power pellets

## Problem
The four power pellets are worth 50 and start a frightened period. The ghosts' reaction belongs to raft d, but the pellet, its score and a `PowerStarted(duration)` event with a per-level duration belong here.

## Non-goals
- Ghost behavior while frightened (f0200 and f0220).

## Solution
_Draft ideas; design happens in ticket-prep._
Power pellets are pellets flagged `power`, and the frightened duration is a row in f0170's `Levels` table. An event is emitted, and a new power pellet during a frightened period restarts the timer.

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
