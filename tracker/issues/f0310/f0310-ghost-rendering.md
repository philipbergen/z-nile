---
id: f0310
type: feature
title: Ghost rendering
raft: 
depends_on: [f0190, f0200, f0210, f0130]
emergent: false
design: draft
created: 2026-09-28
---

# f0310: Ghost rendering

## Problem
f0190–f0220 make ghosts real in Logic, but nothing draws them. Without this the player is chased by invisible enemies. The snapshot from f0120 carries only the player.

## Non-goals
- Ghost behaviour (f0190–f0220). Awareness aids for ghosts out of view (f0320). Sound. Art polish beyond a clear, readable look.

## Solution
_Draft ideas; design happens in ticket-prep._
- Extend the snapshot with each ghost's position, heading and visual state: normal, frightened, frightened-blinking, eyes.
- A client adapter with one model per ghost, interpolated between snapshots the same way as the player's camera (f0130), including across tunnel wraps.
- Visuals: classic colours (red, pink, cyan, orange); blue while frightened; blue and white while blinking; eyes only while returning to the house. Faces point along the heading, so a ghost coming toward the player reads differently from one moving away.
- Ghosts should be tall enough to be seen over a pellet row, and lit so they read in a dark corridor. The exact numbers come from f0130's world scale.

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
