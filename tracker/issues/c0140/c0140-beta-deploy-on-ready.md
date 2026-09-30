---
id: c0140
type: chore
title: Beta deploy on ready
raft: R0080
depends_on: [f0130]
emergent: false
design: draft
created: 2026-09-28
---

# c0140: Beta deploy on ready

## Problem
Nothing is ever running in a real Roblox server except by hand in Studio. The design says every PR that's ready for review should publish to a private **Pickman Beta** experience, so it can be played on real devices (phones included) and so engine-level smoke tests can run (c0030).

## Non-goals
- Publishing to production. Game features.

## Solution
_Draft ideas; design happens in ticket-prep._
- A CI job on `ready_for_review` and on non-draft `synchronize`: `rojo build`, then publish through the Open Cloud Place Publishing API to the Beta universe and place.
- Secrets: `ROBLOX_API_KEY`, `BETA_UNIVERSE_ID`, `BETA_PLACE_ID`. The user creates the experience and the key; prep writes exact steps.
- Only one deploy runs at a time (concurrency group). The PR gets a comment with the version number.

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
