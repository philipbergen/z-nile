---
id: f0120
type: feature
title: Game session server
raft: 
depends_on: [f0110]
emergent: false
design: draft
created: 2026-09-28
---

# f0120: Game session server

## Problem
Each player needs their own maze instance, simulated authoritatively on the server at a fixed tick. Their intents arrive over remotes, and state is replicated to the client that owns it. That's the "solo mazes" decision.

## Non-goals
- Ghosts, pellets and hiscores (later rafts). Matchmaking.

## Solution
_Draft ideas; design happens in ticket-prep._
- A pure `Session` feature (world plus tick) and a server adapter: the player joins, gets a maze instance at a spatial offset, and a fixed-step loop runs.
- Intent validation: rate limits, and only known intents are accepted.
- Snapshot replication at the tick rate.
- The player leaving cleans up.

Also settle during prep:
- **Where the maze lives in the world.** Clients build their own maze locally (f0130), so a player never sees another's maze. Decide whether the server places any maze geometry at all, or only simulates. If it only simulates, the "spatial offset" above is unnecessary; if Roblox physics or character placement needs the server to know a location, keep the offset.
- **The snapshot is a versioned, extensible schema.** a2 sends only the player (tile, sub-tile progress, heading, `wrapped`). Later issues add fields: pellets (f0290), game state and countdown (f0300), ghosts (f0310), score/lives/level (f0180). The schema lives in shared code so client and server can't drift, and the owning client is the only receiver.

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
