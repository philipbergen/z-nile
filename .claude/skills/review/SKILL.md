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
- Design mode: `design-review-NNN.md`, in the raft's directory (`tracker.sh metrics` counts rounds from there).
- Code mode: `review-NNN.md`, in the raft directory.
- `NNN` continues from the highest existing number.

```markdown
# Review NNN: <R0010 | f0010> (<design | code> mode)
Inputs: <commit sha / files reviewed>

### F1 [high] <one-line claim>
Where: <path:line or doc section>
Evidence: <the concrete failing scenario, input, or quote. Not "might be" but "does X when Y">
Critique: <why it matters, and the fix the author will be tempted to make>
Consequences: <take that fix one step further: the new rules, state, edge cases or user decisions it brings, or "none">
Recommendation: <the fix that holds up after its consequences, with the spec cases or decisions it needs>

### F2 [medium] ...

## Judged criteria (code mode only)
- JC1: pass | fail. <reasoning against the rubric>

Verdict: approve | changes
```

**Severity:**
- **high**: a wrong result, a crash, a security or authority hole, an acceptance criterion that's unmet or can be passed by a wrong implementation, or a regression.
- **medium**: a likely future defect, a scalability trap, an architecture rule bent, a missing test for an edge case.
- **low**: a clarity or maintainability improvement.

**Think one step further.** A finding isn't finished at "here's the fix". Say what new rule, state, edge case or user decision the fix brings, and how it interacts with existing rules, and make the Recommendation cover it, including its spec cases, so it doesn't come back as next round's finding.

Don't pad the review. Zero findings with `Verdict: approve` is a valid result. Use `approve` only when no high or medium findings remain.

On a re-review round, first read the previous `review-NNN.md` and `refute-NNN.md`.
- If a refutation is right, drop that finding.
- If it's wrong, repeat it with the new evidence.

## Visible record
In code mode the PR shows the review as it happens: the author pushes and posts a "started" comment before you begin, and commits, pushes and summarizes `review-NNN.md` when you finish. So:
- Write `review-NNN.md` in full; findings that exist only in your reply are lost. Write only that file: don't commit, push, comment on the PR or leave other files in the tree (the author's commit uses `git add -A`).
- On a re-review, list withdrawn findings in a non-heading line under `Inputs:`, for example `Dropped from review-001: F2, F4`. Give a repeated finding a new id and say `(repeat of review-001 F3)` in its claim. Every `### F<n>` heading is a finding that `tracker.sh done` requires an answer to, and ids restart at F1 each round.
- Design mode runs in the prep worktree before any PR exists, so it is exempt; its files are committed with the prep commit and ride in the prep PR.

## Design mode (from ticket-prep)
Attack all of the following:
0. **Rules and mutants**: audit each issue's Rules and mutants table. Every behavioural rule in the Design needs a row. Rows marked `run` were mutation-tested on a prototype in prep, with the outcome recorded in Unknowns & experiments; check that record, and spot-run only the rows you doubt. `reasoned` rows weren't run (the reason is in Unknowns & experiments), so judge them by reading, or spot-check them with a scratch copy. A missing row, a row whose spec case can't fail, or a plausible mutant nobody listed is a finding.
1. **Unknowns**: every assumption that isn't proven, especially about Roblox or engine behavior, replication, or performance. Is each one an experiment with a pass/fail question and a fallback?
2. **Acceptance criteria**:
   - Can a wrong or hard-coded implementation pass `check.sh`?
   - Does every Checked criterion correspond to a real check?
   - Could a Judged or Observed criterion be turned into a measurable proxy?
3. **Completeness**: missing edge cases, such as empty input, bounds, simultaneous events, respawns, frame-rate independence, or player disconnects.
4. **Regressions**: which existing behavior could break, and is it guarded? Check each issue's `Overrides:` line: for every Touched path run `lune run scripts/affected -- <path>` and `grep -rlF -e <path> tests/acceptance` (`ALL` carries no list: grep alone, also with the basename), and confirm that every promoted spec the design would turn red is named there, with its chore in `depends_on` unless the issue is itself a chore. An unnamed override, a missing line or an unfilled placeholder is **high**.
5. **Architecture**: is Logic kept pure, and are requires legal? Is every new dependency declared in `architecture.md`, and is the graph still acyclic? Is the server authoritative?
6. **Scalability, maintainability and usability**: are they addressed concretely?
7. **Raft coherence**: do the issue designs agree with the whole-raft design and with each other, and is the order right?
8. **Executability**: could an agent that has never seen this repo deliver it from the documents alone, without asking a question?
9. **Repository safety**: could any spec, `check.sh` or script in this raft change the real repository (testing skill, "Specs never touch the real repository")? Every command that changes anything must run in a fixture under `.cache/<unique name>` with its own repository, committing as `@example.invalid`. Check especially what the runner can't enforce (that section's "Caught only by review" list). Any path to the real repository, or any weakening of its guards, is **high**.

## Stream mode (execute-raft Phase 2B)
A stream review is a cheap first filter on **one issue's** work, run by a clean **Sonnet** subagent before the lead merges the stream. It never replaces the code review of the whole raft (Code mode, Opus).
- **Scope**: `git diff <raft branch>...ws-<issue>`, that issue's document, `check.sh` and acceptance specs. Run the stream's checks (`scripts/tracker.sh check <issue>`, `scripts/check.sh --affected`) in the stream worktree. Check that the diff touches only the issue's Touched modules, its own document, and its `stream-review-<issue>-*` and `stream-refute-<issue>-*` files; anything else is a finding.
- **Output**: only `tracker/rafts/active/<R-id>/stream-review-<issue>-NNN.md`, written in the stream worktree, in the format above (no Judged section: the Opus review rules on Judged criteria). Number rounds from 001; there are at most two. The author answers in `stream-refute-<issue>-NNN.md`.
- These files are not review rounds: `tracker.sh done` and `metrics` ignore them.

## Code mode (before the PR is marked ready)
Inputs: `scripts/tracker.sh sync --fetch` (never a merge: a merge would add a commit and move the sha the author announced), then `git diff origin/main...HEAD`, the raft and issue documents, and the `check.sh` files.
A code-mode Recommendation never asks the author to edit sequestered `check.sh` files or acceptance specs, or to decide product questions. If that's the only fix, say the author must escalate (execute-raft stop conditions).
1. **Correctness**: run the code in your head against edge cases, and read the tests critically. Run `scripts/check.sh --full` and each `tracker.sh check <id>` yourself.
2. **Sequestration**: `git fetch origin main && git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` must list nothing except `R100` renames (the move to `active/`). Any other change is **high**. The three-dot form shows only what this branch changed, not what `main` brought in.
3. **Weak tests**: tests that assert on internals, lack a negative case, would pass with a stub, or depend on the wall clock or randomness.
4. **Design adherence**: does the code match the Design? Is each deviation recorded with a reason?
5. **Architecture rules** from the skill, including thin adapters and server authority.
6. **Performance**: per-frame allocations, O(n²) work in a tick, and replication volume.
7. **Judged criteria**: give a ruling on each against its rubric.
8. **Repository safety**: no spec, `check.sh` or script in the diff may change the real repository, run a command that changes anything outside a `.cache` fixture, or weaken a guard: `tests/lib/fence.luau`, `scripts/lib/fence.sh`, `scripts/lib/git-hooks/`, the fence in `scripts/lib/ac.sh`, `tests/tooling/repo-fence.spec.luau`. Check the "Caught only by review" list in the testing skill's "Specs never touch the real repository" section line by line. Any such path is **high**.
