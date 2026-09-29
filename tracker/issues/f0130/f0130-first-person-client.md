---
id: f0130
type: feature
title: First person client
raft: 
depends_on: [f0100, f0120]
emergent: false
design: draft
created: 2026-09-28
---

# f0130: First person client

## Problem
The player has to *see* the maze from inside it: walls built from the maze data, a first-person camera that follows the replicated position smoothly with free look, and keyboard/mouse input turned into intents. This is the "opens and plays in Roblox" half of raft a.

## Non-goals
- Touch input (raft f). HUD (f0180). Art polish.

## Solution
_Draft ideas; design happens in ticket-prep._
- A client adapter that builds wall parts from the maze. A place test checks the geometry against the maze.
- A camera locked to the first person: yaw and pitch from the mouse, snap-to-heading, interpolation between snapshots.
- A key map producing intents.
- An Observed check in Studio, kept to the minimum.

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
