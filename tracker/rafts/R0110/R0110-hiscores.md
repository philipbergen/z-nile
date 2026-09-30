---
id: R0110
type: feature
title: Hiscores
single: false
issues: [f0230, f0240, f0250]
design: draft
created: 2026-09-30
---

# R0110: Hiscores

## Theme
Roadmap raft **e**: a global all-time top N plus daily and weekly boards, submitted only by the server from its own simulated result at game over. Logic talks to a storage interface (a fake in tests, Roblox's ordered store in the adapter), and Beta and production use separate stores. See the Hiscores section of `tracker/game-design.md`.

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
     "Done" == `scripts/tracker.sh done R0110` succeeds. -->

## Risks & rollback

## Addressed during execution
<!-- Emergent issues created and fixed in this PR (id, why it could not be postponed). -->
