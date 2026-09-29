---
id: c0090
type: chore
title: Game sim harness
raft: 
depends_on: []
emergent: false
design: draft
created: 2026-09-28
---

# c0090: Game sim harness

## Problem
Pillar 2 of the game design needs every game rule to be checked headless in CI, but there's no way yet to *run the game* outside Roblox: stepping a world on a fixed tick with scripted intents and asserting on what happens. Without that, "collisions work" or "ghosts catch an idle player" can only be checked by hand in Studio.

## Non-goals
- The game rules themselves: a2 onward. Rendering, and any Roblox APIs.

## Solution
_Draft ideas; design happens in ticket-prep._
- A `tests/lib/sim.luau` harness: build a world from a maze string, then feed a script of intents at ticks with `sim.run(world, script, ticks)` and get back a trace of events and states.
- Scenario specs that read like stories (`at tick 0 intent Left; expect tile (3,5) at tick 12`).
- Replay files saved for failures.
- A performance budget: N ticks with M mazes in under X ms. This becomes a regression spec.
- A place in the testing skill as a new test tier.

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
