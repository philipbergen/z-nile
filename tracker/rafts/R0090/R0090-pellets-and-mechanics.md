---
id: R0090
type: feature
title: Pellets and mechanics
single: false
issues: [f0150, f0160, f0170, f0180, f0290, f0300]
design: draft
created: 2026-09-30
---

# R0090: Pellets and mechanics

## Theme
Roadmap raft **c**, the first raft that makes it a game: eating, score, lives, levels, pellets drawn, the HUD, and start / game over / play again. On its own it's a solo pellet-eating game with no danger. It builds on a2 (R0040: maze, movement, session, first-person client), and its issues extend the Session and the snapshot schema that raft defined. Prep should decide whether six issues fit one reviewable PR or split it (for example scoring and rules, then HUD, rendering and game flow).

## Whole-raft design
<!-- Module map, the interfaces between member issues, data flow. Diagram if it helps.
     Every issue design must agree with this. Include any tracker/architecture.md changes. -->

## Order & dependencies
<!-- Execution order of member issues and why. -->

## Experiments phase
<!-- All unknowns across the raft, run FIRST. For each: question, command, result (if run in prep),
     fallback. If an experiment fails without a fallback: stop and escalate. -->

## Exit criteria
<!-- Exact, machine-checkable goal state. Implemented by this raft's check.sh (RCn labels).
     "Done" == `scripts/tracker.sh done R0090` succeeds. -->

## Risks & rollback

## Addressed during execution
<!-- Emergent issues created and fixed in this PR (id, why it could not be postponed). -->
