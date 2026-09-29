---
id: f0170
type: feature
title: Lives and levels
raft: 
depends_on: [f0150]
emergent: false
design: draft
created: 2026-09-28
---

# f0170: Lives and levels

## Problem
A game needs a beginning and an end: 3 lives, game over, and clearing every pellet advancing to the next level, which resets the maze with harder parameters (speeds, frightened duration).

## Non-goals
- What causes a death: ghosts (f0220). Hiscore submission (f0240).

## Solution
_Draft ideas; design happens in ticket-prep._
A `Game` state machine: ready, playing, dying, level clear, game over. Per-level parameter tables (classic values). Deaths are an input event, so this is testable before ghosts exist.

**This issue owns the one `Levels` table** (a pure feature in the architecture map): per-level player and ghost speeds, the frightened duration, blink count, the scatter/chase schedule and house release values. f0160, f0200 and f0210 read from it and don't keep their own copies. Rows for data those issues introduce are added by those issues.
How the states are presented on the client (countdown, death, level clear, game over, play again) is f0300.

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
