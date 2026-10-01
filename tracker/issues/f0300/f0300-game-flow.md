---
id: f0300
type: feature
title: Game flow
raft: R0130
depends_on: [f0170, f0130]
emergent: false
design: draft
created: 2026-09-28
---

# f0300: Game flow

## Problem
f0170 gives Logic a game state machine (ready, playing, dying, level clear, game over), but nothing covers how a player moves through it in Roblox:
- when a game starts after the player joins;
- what the player sees while dying, on level clear, and at game over;
- how they play again without rejoining.
Right now a finished game would leave the player frozen in the maze with no way forward.

## Non-goals
- Hiscore submission and the board (f0240, f0250). A lobby, menus beyond start/play-again, matchmaking. Mobile-specific layout (f0280).

## Solution
_Draft ideas; design happens in ticket-prep._
- The game state and a countdown are part of the snapshot, so the client presents it and never decides it.
- Join: the maze builds, then a short "Ready!" countdown in the `ready` state before `playing` (classic feel). Same after each death and each level clear.
- Dying: movement freezes, and a brief camera effect plays; then positions reset (Logic already resets them).
- Level clear: a brief maze flash, then the maze reloads with every pellet back.
- Game over: a screen with the final score and level, and a **Play again** intent sent to the server, which validates it (only in `gameover`) and starts a new session in the same maze instance.

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
