---
id: c0410
type: chore
title: Review second order
raft: 
depends_on: []
emergent: false
design: draft
created: 2026-09-30
---

# c0410: Review second order

## Problem
Design reviews take too many rounds. R0040 and R0060 each needed four, and R0050 four as well; the skill's cap is three. Two causes stood out in this session (2026-09-29):
- **Fixes create the next round's findings.** A finding ends at `Fix:`, and nobody asks what that fix leads to. For example, R0040's cornering grace (round 2) led directly to round 3's and round 4's highs: grace after a turn, presses two ticks late, the junction the player meant. All three were visible from round 2.
- **Coverage is sampled, not audited.** Each fresh reviewer hunts open-ended and finds a different subset. Nearly every high was a behavioural rule with no spec case that kills a plausible wrong implementation.

The user wants to try a cheap fix first (2026-09-29), combining two ideas:
- **Second-order findings**: review → critique → what would the fix lead to? → recommendation.
- **A rule-and-mutant table**: every behavioural rule → the spec case that pins it → the planted bug that case kills. The author writes it in prep, and the reviewer audits it for missing rows.

Cost matters. There's no parallel reviewers for now; measure whether rounds drop first.

## Non-goals
- Parallel focused reviewers in round 1 (deferred by the user for cost).
- A "Decisions needed" section, a lessons checklist, and narrower re-reviews (candidates for later, if this doesn't converge enough).
- Changing the round cap.

## Solution
Ideas:
- **Review skill**: the finding format gains `Critique`, `Consequences` (the new rules, state, edge cases and decisions the obvious fix brings) and `Recommendation` (the fix that holds up after that, with its spec cases). Design mode also audits the issue's rule-and-mutant table for missing rows.
- **Issue template and ticket-prep**: add a "Rules and mutants" table under Test plan, filled in during prep from the mutation check. Refute files state the recommendation as applied, plus any consequences rejected and why.
- **Measure**: note the number of review rounds per raft in the raft doc, to compare before and after.

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
