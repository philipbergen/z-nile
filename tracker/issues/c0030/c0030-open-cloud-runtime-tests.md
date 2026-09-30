---
id: c0030
type: chore
title: Open Cloud runtime tests
raft: R0080
depends_on: []
emergent: false
design: draft
created: 2026-09-28
---

# c0030: Open cloud runtime tests

## Problem
- c0020's place tests prove **structure**, not **behavior**. Adapter code, meaning server scripts, remotes and the client camera and input, never runs outside Studio. That leaves any criterion about adapter behavior as Observed, meaning manual.
- Roblox Open Cloud's Luau Execution API can run Luau inside a real server of a published place, and could turn those into Checked criteria.
- It needs an Open Cloud API key, a universe/place to publish to, and CI secrets. The human provided these on 2026-09-28 (see Resources).

## Resources (provided by the human, 2026-09-28)
| what | where | value |
|---|---|---|
| experience | Creator Hub, private | `Pickman (Beta)` |
| universe ID | GitHub repo variable `ROBLOX_BETA_UNIVERSE_ID` | `10768553777` |
| place ID | GitHub repo variable `ROBLOX_BETA_PLACE_ID` | `82331952549326` |
| API key | GitHub repo secret `ROBLOX_API_KEY` | scoped to that experience: `universe-places` write, `luau-execution-sessions` read+write; IP allowlist `0.0.0.0/0`; has an expiry |

- The key is a secret: it only exists in CI. Local runs need it exported as `ROBLOX_API_KEY`, and specs must skip (not fail) when it is absent.
- Open question for ticket-prep: publishing test builds to the beta place replaces what beta testers play. Either test against a separate private `Pickman (CI)` experience (needs a new key scope and variables from the human), or accept the overlap while beta is small.
- Unverified: nothing has used the key yet. An early experiment should publish once and run one trivial Luau execution task.

## Non-goals
- Deploying to the beta place for testers; that is a separate deploy chore.

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
