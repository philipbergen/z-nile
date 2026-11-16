---
title: A step the raft says a person runs before ready has a dated result or a waiver before the raft is readied
when: both
tags: [ready, experiments, human-step]
check: Does the raft document or any member name a step that must happen before `./zn ready` (a live-place experiment, a Studio check), and does its place for the result hold a dated result or a user decision that waives it?
---
`./zn ready` checks the designs, the approvals and the dependencies. It does not read a raft document's own prose rules. A raft can say "the user runs E6 before ready; if not, unfold this member" and still be readied, built and reviewed with that line reading "not run yet".

**Why:** R0094 (2026-11-15). Its "Phase 1 checks that wait for a live place" paragraph said f0148's E5 and E6 (a real DataStore, a phone) must be run by the user before `./zn ready R0094`, and that f0148 is unfolded otherwise. The lead compared the members' scope with their captures and checked the specs and dependencies, but did not read the raft's Order and Experiments paragraphs for steps of its own. All four layers were built before code review 001 F1 found it. The user then decided to land and test afterwards, which they could have decided before a line was written.

**How to apply:** before `./zn ready`, search the raft document and each member for "before `ready`", "before ready", "human step" and "not run yet". For each hit, either the result is recorded where the document says, or ask the user now: run it, waive it (recorded as a `Decided with the user` line), or take the fallback the document names. An executor who finds such a line unanswered in Phase 0 stops before building the member it guards.
