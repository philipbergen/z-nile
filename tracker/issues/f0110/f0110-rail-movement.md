---
id: f0110
type: feature
title: Rail movement
raft: 
depends_on: [f0100, c0090]
emergent: false
design: draft
created: 2026-09-28
---

# f0110: Rail movement

## Problem
The player has to move through the maze the way the game design describes: rail movement with buffered turns, stopping at walls and wrapping through tunnels. The movement must be deterministic and frame-rate independent, so collisions can be proven in CI.

## Non-goals
- Look/camera (f0130). Speed tables per level (c raft).

## Solution
_Draft ideas; design happens in ticket-prep._
A pure `Movement` feature that steps a position, heading and turn buffer by `dt` using intents. It centres on corridor centrelines, takes a turn at the first tile where the exit exists, reverses immediately on `Back`, and makes wall contact stop at the tile edge. The scenario specs use the c0090 sim harness.

Edge cases prep must decide and specify:
- **Starting heading** at spawn and after each reset (classic: moving left).
- **Stopped at a wall**: a `Left`/`Right`/`Back` intent whose exit exists applies immediately; the player doesn't need to be moving.
- **`Forward`**: clears any buffered turn, so the next junction is passed straight through. Decide whether it also restarts movement when stopped.
- **Door tile**: impassable for the player (via f0100's passability query).
- **Tunnels**: position wraps; the step reports a `wrapped` flag so the client (f0130) can skip interpolating across the maze.

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
