---
id: R0070
type: chore
title: Review second order
single: true
issues: [c0410]
design: ready
created: 2026-09-30
---

# R0070: Review second order

## Theme
A single-issue chore raft for c0410. Design reviews have been taking 3–5 rounds; the baseline is in c0410's Problem. The user chose to try the cheap fix first (2026-09-29): **second-order findings** (review → critique → consequences → recommendation) and an author-written **Rules and mutants** table that reviewers audit. Parallel reviewers are deferred for cost. The raft also adds a review-rounds table to `tracker.sh metrics`, so the effect is measured, not guessed.

## Whole-raft design
See c0410's Design:
- the review skill's finding format and two paragraphs;
- one new table in the issue template;
- two additions to ticket-prep;
- one table in `tracker.sh metrics`.

`tracker.sh done`'s review parsing is untouched, and AC1 pins that the new format still parses. No change to `src/`, `tests/`, `tracker/architecture.md` or other skills.

## Order & dependencies
One issue: review skill, then template and ticket-prep, then metrics. It has no dependencies. It takes effect for rafts prepped after it merges.

## Experiments phase
All run in prep, all PASS: E1 (the format still parses for `done`) and E2 (a prototype passes 5/5 and the tooling specs, and every `run` row in c0410's Rules and mutants table fails the check). The executor has no Phase 1 work.

## Exit criteria
Implemented by `check.sh`:
- **RC0**: the full repo gate passes, c0410's `check.sh` passes (AC1–AC5), and `promote-check` passes.

## Risks & rollback
- **Risk: the extra fields turn into boilerplate** ("Consequences: none" everywhere). The measure is the metrics table. If rounds don't drop over the next few rafts, the next step is the deferred ideas in c0410's Non-goals.
- **Risk: reviews get longer and cost more per round.** That's one line per finding. The bet is that it saves whole rounds.
- **Rollback**: revert the PR. Only docs and one metrics table change.

## Addressed during execution
