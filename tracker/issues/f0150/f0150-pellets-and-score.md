---
id: f0150
type: feature
title: Pellets and score
raft: 
depends_on: [f0110]
emergent: false
design: draft
created: 2026-09-28
---

# f0150: Pellets and score

## Problem
Pac-Man is about eating: a pellet on every pellet tile the maze text authors (f0100), eaten when the player enters the tile, adding points (10 each). The score has to be tracked authoritatively.

## Non-goals
- Power pellets' effect on ghosts (raft d). HUD (f0180).

## Solution
_Draft ideas; design happens in ticket-prep._
Pellet state per maze instance. Eating runs on tile entry inside the movement step. Score events are emitted for the HUD and hiscores. Sim scenarios cover eating along a corridor and never eating the same pellet twice.

Drawing pellets and sending eaten pellets to the client is f0290.

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
