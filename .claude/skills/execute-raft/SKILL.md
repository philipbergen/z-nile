---
name: execute-raft
description: The autonomous execution protocol for one raft - one branch, one PR, experiments first, tests first, spend-tracked commits, adversarial code review, done. Use when implementing a raft (or when handed a prompt from make-prompt).
---

# Execute a raft

Input: a raft ID (`R0010`) whose issues are `design: ready`.
Output: one PR, taken out of draft by `scripts/tracker.sh done R0010`.

Work through the phases in order and don't skip any. Wherever you are unsure, the tracker, architecture and testing skills are binding.

## Phase 0: Claim (in the first minutes)
1. `git switch main && git pull --ff-only`, then confirm `scripts/check.sh --full` passes on main.
   - **If main is red, stop.** Report it; don't fix main inside this raft.
2. `scripts/tracker.sh start R0010`. This creates the branch, moves the items to `active/`, commits, pushes, and opens a **draft** PR.
3. Read the raft document, then every issue document and `check.sh`, in the raft's order.
   - Write down, for yourself, which files each issue touches.

## Phase 1: Experiments (fail fast)
- For every unknown in the raft's and issues' "Unknowns & experiments" that has no recorded result: run the experiment in the issue's `experiments/` directory, and record the result in the issue document.
- **If an experiment fails:**
  - Switch to the documented fallback, and note that in the issue.
  - If there's no fallback: **stop** and escalate (see Stop conditions).
- Commit: `scripts/tracker.sh commit -m "R0010: experiments" --time <minutes>`.

## Phase 2: Implement, one issue at a time in the raft's order
For each issue:
1. `scripts/tracker.sh focus <issue>`.
2. **Tests first.**
   - Write the specs in the issue's Test plan under `tests/`. These are your own unit, contract and regression specs.
   - The sequestered acceptance specs in `tracker/issues/<id>/acceptance/` already exist from prep. Don't modify or move them; `done` promotes them.
   - Run them and confirm that each one **fails for the expected reason**, not because of a syntax error or a missing file.
3. **Implement** the Design exactly, following the Implementation steps.
   - Iterate with `scripts/check.sh --affected`.
   - Commit at meaningful green steps with `scripts/tracker.sh commit -m "<issue>: <what>"`, adding `--time` when you know it.
4. **Finish the issue**: `scripts/tracker.sh check <issue>` shows every AC as PASS. Then append a Verification log entry to the issue document and commit.
5. **Deviations**:
   - If the design turns out to be wrong in a small, local way (for example a name or a helper split), adjust it and record the deviation, with the reason, in the issue's Verification log.
   - If it's wrong in a way that changes a public API, a cross-feature dependency or an acceptance criterion, **stop** and escalate.
6. **Emergent problems**: follow "Emergent issues" in the tracker skill. Only fix them now if they can't be postponed.

## Phase 3: Whole-raft verification
1. `bash "$(scripts/tracker.sh find R0010)/check.sh"`. Every RC line must PASS.
2. Double-check that `scripts/check.sh --full` passes as well.
3. **Sequestration check**: `git diff <start-commit> -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` must be empty.
   - The start commit is the one with the subject `tracker: start R0010`.

## Phase 4: Adversarial code review (a clean reviewer)
1. Start a **clean** reviewer. It has none of your context and gets only these inputs:
   - the `review` skill (code mode);
   - `git diff main...HEAD`;
   - the raft and issue documents and `check.sh` files;
   - read access to the repo.
   In Claude Code, that's a fresh subagent. For other agents, use a new session or context that receives only those inputs.
2. The reviewer writes `review-NNN.md` in the raft directory (starting at 001), including a ruling on every Judged criterion.
3. You respond in `refute-NNN.md`, with one line per finding:
   - `- F3: fixed <short sha>: <what changed>`, or
   - `- F3: refuted: <argument with evidence>`.
   Only refute when you can show the reviewer is wrong: a test, a spec, or the design text. Everything else gets fixed.
4. Commit the fixes, the review file and the refute file.
5. **Re-review** with `review-NNN+1.md` from a *new* clean reviewer if any of these are true:
   - any high-severity finding was fixed;
   - the fixes changed a public API or the design;
   - the fixes are more than about 15% of the PR's lines;
   - a Judged criterion was ruled fail.
6. **Cap: 3 rounds.** If round 3 still isn't resolved, stop and escalate.

## Phase 5: Done
1. Append each issue's final Verification log entry and fill in the raft's "Addressed during execution". Commit.
2. `scripts/tracker.sh done R0010`. It re-verifies everything, moves the items to `done/`, pushes, and marks the PR ready.
3. Write the final report (below). This goes in your reply, and also as a PR comment: `gh pr comment --body-file -`.

## Stop conditions (escalate; don't improvise)
Stop and report if any of these happen:
- An experiment fails and has no fallback.
- The design is wrong beyond local adjustments.
- A `check.sh` or acceptance spec is wrong or can't be satisfied.
- Main is red.
- A tool is missing and `SETUP.md` doesn't fix it.
- Round 3 of review is still unresolved.
- An action would require a secret or credential you don't have.

To escalate:
1. Commit whatever is green.
2. Push.
3. Leave the PR in **draft**.
4. Post a PR comment that starts with `BLOCKED:` and covers what you tried, the evidence, and the decision you need.

## Final report format
```
R0010: <title>. <READY | BLOCKED>
PR: <url>
Criteria: <n>/<n> Checked PASS (tracker.sh done output), Judged: <rulings>
Observed (human, in Studio): <numbered steps from the issues' Observed sections>
Deviations: <issue: what and why> | none
Emergent issues: <ids and one line each> | none
Follow-ups filed: <ids> | none
Spend: <raft spend.md totals>
```
