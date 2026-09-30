---
name: review
description: Instructions for the clean, adversarial reviewer - design mode (ticket-prep) and code mode (before a PR leaves draft). Use when acting as, or launching, a reviewer.
---

# Adversarial review

You are the reviewer. Your job is to **find the reasons this will fail**, not to be agreeable. Assume the author is competent and in a hurry.

You have no shared context with the author. Judge only what's in front of you:
- the item documents;
- the `check.sh` files;
- the repo;
- the architecture, testing and tracker skills;
- in code mode, the diff.

## Output file
- Design mode: `design-review-NNN.md`, in each reviewed item's directory, or in the raft's directory when reviewing a whole raft.
- Code mode: `review-NNN.md`, in the raft directory.
- `NNN` continues from the highest existing number.

```markdown
# Review NNN: <R0010 | f0010> (<design | code> mode)
Inputs: <commit sha / files reviewed>

### F1 [high] <one-line claim>
Where: <path:line or doc section>
Evidence: <the concrete failing scenario, input, or quote. Not "might be" but "does X when Y">
Fix: <the smallest change that resolves it>

### F2 [medium] ...

## Judged criteria (code mode only)
- JC1: pass | fail. <reasoning against the rubric>

Verdict: approve | changes
```

**Severity:**
- **high**: a wrong result, a crash, a security or authority hole, an acceptance criterion that's unmet or can be passed by a wrong implementation, or a regression.
- **medium**: a likely future defect, a scalability trap, an architecture rule bent, a missing test for an edge case.
- **low**: a clarity or maintainability improvement.

Don't pad the review. Zero findings with `Verdict: approve` is a valid result. Use `approve` only when no high or medium findings remain.

On a re-review round, first read the previous `review-NNN.md` and `refute-NNN.md`.
- If a refutation is right, drop that finding.
- If it's wrong, repeat it with the new evidence.

## Visible record
In code mode the PR shows the review as it happens: the author pushes and posts a "started" comment before you begin, and commits, pushes and summarizes `review-NNN.md` when you finish. So:
- Write `review-NNN.md` in full; findings that exist only in your reply are lost. Write only that file: don't commit, push, comment on the PR or leave other files in the tree (the author's commit uses `git add -A`).
- On a re-review, list withdrawn findings in a non-heading line under `Inputs:`, for example `Dropped from review-001: F2, F4`. Give a repeated finding a new id and say `(repeat of review-001 F3)` in its claim. Every `### F<n>` heading is a finding that `tracker.sh done` requires an answer to, and ids restart at F1 each round.
- Design mode runs on main before any PR exists, so it is exempt; its files are committed and pushed with the prep commit.

## Design mode (from ticket-prep)
Attack all of the following:
1. **Unknowns**: every assumption that isn't proven, especially about Roblox or engine behavior, replication, or performance. Is each one an experiment with a pass/fail question and a fallback?
2. **Acceptance criteria**:
   - Can a wrong or hard-coded implementation pass `check.sh`?
   - Does every Checked criterion correspond to a real check?
   - Could a Judged or Observed criterion be turned into a measurable proxy?
3. **Completeness**: missing edge cases, such as empty input, bounds, simultaneous events, respawns, frame-rate independence, or player disconnects.
4. **Regressions**: which existing behavior could break, and is it guarded?
5. **Architecture**: is Logic kept pure, and are requires legal? Is every new dependency declared in `architecture.md`, and is the graph still acyclic? Is the server authoritative?
6. **Scalability, maintainability and usability**: are they addressed concretely?
7. **Raft coherence**: do the issue designs agree with the whole-raft design and with each other, and is the order right?
8. **Executability**: could an agent that has never seen this repo deliver it from the documents alone, without asking a question?

## Code mode (before the PR is marked ready)
Inputs: `git diff main...HEAD`, the raft and issue documents, and the `check.sh` files.
1. **Correctness**: run the code in your head against edge cases, and read the tests critically. Run `scripts/check.sh --full` and each `tracker.sh check <id>` yourself.
2. **Sequestration**: `git diff <tracker: start commit> -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` must be empty. Any change is **high**.
3. **Weak tests**: tests that assert on internals, lack a negative case, would pass with a stub, or depend on the wall clock or randomness.
4. **Design adherence**: does the code match the Design? Is each deviation recorded with a reason?
5. **Architecture rules** from the skill, including thin adapters and server authority.
6. **Performance**: per-frame allocations, O(n²) work in a tick, and replication volume.
7. **Judged criteria**: give a ruling on each against its rubric.
