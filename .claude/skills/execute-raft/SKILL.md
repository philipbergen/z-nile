---
name: execute-raft
description: The autonomous execution protocol for one raft - one branch, one PR, experiments first, tests first, spend-tracked commits, adversarial code review, done. Use when implementing a raft (or when handed a prompt from make-prompt).
---

# Execute a raft

Input: a raft ID (`R0010`) whose issues are `design: ready`.
Output: one PR, taken out of draft by `scripts/tracker.sh done R0010`, then merged by you (Phase 6).

Work through the phases in order and don't skip any. Wherever you are unsure, the tracker, architecture and testing skills are binding.

## Phase 0: Claim (in the first minutes)
1. Work in the raft's worktree: `cd "$(scripts/tracker.sh worktree R0010)"` (tracker skill, Worktrees). It branches from a freshly fetched `origin/main`. Never switch branches in the main checkout, and run everything below from this directory. Confirm `scripts/check.sh --full` passes here.
   - **If main is red, stop.** Report it; don't fix main inside this raft.
2. `scripts/tracker.sh start R0010`. This creates the branch (if the worktree isn't already on it), moves the items to `active/`, commits, pushes, and opens a **draft** PR.
3. Read the raft document, then every issue document and `check.sh`, in the raft's order.
   - Write down, for yourself, which files each issue touches.

## Phase 1: Experiments (fail fast)
- For every unknown in the raft's and issues' "Unknowns & experiments" that has no recorded result: run the experiment in the issue's `experiments/` directory, and record the result in the issue document.
- **If an experiment fails:**
  - Switch to the documented fallback, and note that in the issue.
  - If there's no fallback: **stop** and escalate (see Stop conditions).
- Commit: `scripts/tracker.sh commit -m "R0010: experiments" --time <minutes>`, then post a PR comment listing each experiment and its result.

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
4. **Finish the issue**: `scripts/tracker.sh check <issue>` shows every AC as PASS. Then append a Verification log entry to the issue document, commit, and post a PR comment `<issue> done: n/n ACs PASS`.
5. **Deviations**:
   - If the design turns out to be wrong in a small, local way (for example a name or a helper split), adjust it and record the deviation, with the reason, in the issue's Verification log.
   - If it's wrong in a way that changes a public API, a cross-feature dependency or an acceptance criterion, **stop** and escalate.
6. **Emergent problems**: follow "Emergent issues" in the tracker skill. Only fix them now if they can't be postponed.

## Phase 3: Whole-raft verification
When the steps below pass, post a PR comment with the RC results.

1. `bash "$(scripts/tracker.sh find R0010)/check.sh"`. Every RC line must PASS.
2. Double-check that `scripts/check.sh --full` passes as well, and that `scripts/tracker.sh promote-check R0010` passes. It dry-runs the move of the acceptance specs into `tests/`. If it fails because of a sequestered spec, stop and escalate now, not at `done`.
3. **Sequestration check**: `git diff <start-commit> -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` must be empty.
   - The start commit is the one with the subject `tracker: start R0010`.

## Phase 4: Adversarial code review (a clean reviewer)
The PR is the visible record of the work. Push and post a PR comment (`gh pr comment --body-file -`) at each step below, so a human watching sees the review start, its findings, and how they were answered. Never hold review state locally. If a push or `gh` call fails, retry once, then carry on and mention the failure in your next comment; don't block on it. `tracker.sh commit` skips the push when there is no upstream, so check that `git status -sb` shows no `ahead`.

1. **Before launching**: commit any pending work with `tracker.sh commit` so the reviewer sees exactly what the PR shows, and post the comment `Review NNN started at <short sha> (code mode)`.
2. Start a **clean** reviewer. It has none of your context and gets only these inputs:
   - the `review` skill (code mode);
   - `git fetch origin main && git diff origin/main...HEAD` (the local `main` isn't kept current);
   - the raft and issue documents and `check.sh` files;
   - read access to the repo.
   In Claude Code, that's a fresh subagent. For other agents, use a new session or context that receives only those inputs.
   Run the reviewer on **Opus 5.5**, even if you run on a cheaper model: a reviewer on the author's model shares its blind spots, and review is a small share of the spend. In Claude Code, pass `model: "opus"` to the Agent tool. Don't substitute another model, such as Fable or Sonnet. Outside Claude Code, use Opus 5.5 if the harness offers it; otherwise say which model reviewed in the review PR comment. Tell the reviewer to write only `review-NNN.md`: no commits, pushes, PR comments or stray files.
3. The reviewer writes `review-NNN.md` in the raft directory (starting at 001), including a ruling on every Judged criterion. **When the reviewer finishes**, you commit it: `scripts/tracker.sh commit -m "R0010: review-NNN" --time 0` (this pushes; `--time 0` keeps the reviewer's runtime out of author spend). Then comment with the verdict and the finding count by severity, listing each `F<n> [severity] <claim>`.
4. **If the verdict is `approve` with no findings, go to Phase 5**: there is no refute file, and the verdict comment is the record. Otherwise respond in `refute-NNN.md`, with one line per finding:
   - `- F3: fixed <short sha>: <what changed>`, or
   - `- F3: refuted: <argument with evidence>`.
   Only refute when you can show the reviewer is wrong: a test, a spec, or the design text. Everything else gets fixed.
5. Commit each fix as you make it (pushed by `tracker.sh commit`), then commit the refute file. Post a comment `Review NNN addressed`, pasting the refute file's lines.
6. **Re-review** with `review-NNN+1.md` from a *new* clean reviewer if any of these are true (repeat from step 1):
   - any high-severity finding was fixed;
   - the fixes changed a public API or the design;
   - the fixes are more than about 15% of the PR's lines;
   - a Judged criterion was ruled fail;
   - you refuted (rather than fixed) any high finding or failed Judged criterion, so a new reviewer rules on the refutation.
7. **Cap: 3 rounds.** The reviewer's own file decides what is significant, not your answer to it. If `review-003.md` contains any **high** finding or any Judged criterion ruled fail, the merge is blocked and the human is engaged, whether or not you fixed it, because no reviewer remains to verify the fix or a refutation. Stop and escalate. (Rounds 1-2 need no such rule: a fresh reviewer in the next round rules on every refutation.) Medium and low findings in `review-003.md` do not block, and you can't downgrade the severity the reviewer wrote. Fix them (answer `fixed`) if the fix is small; otherwise: file each with `tracker.sh new issue`, answer it in `refute-003.md` as `- F<n>: refuted: below the merge threshold (medium|low), filed as <id>`, and quote every such line in the round's PR comment. This is an interim form until c0360 adds a real `deferred` answer, because `tracker.sh done` accepts only `fixed` or `refuted`. It is the sole exception to "only refute when the reviewer is wrong". Then continue to Phase 5.

## Phase 5: Done
1. Append each issue's final Verification log entry and fill in the raft's "Addressed during execution". Commit.
2. `git fetch origin main` and merge it into the branch now (renumber colliding IDs, rerun `scripts/check.sh --full`, commit), so the PR is up to date before `done` and nothing needs changing after it.
3. `scripts/tracker.sh done R0010`. It re-verifies everything, moves the items to `done/`, pushes, and marks the PR ready.
4. Post a PR comment `Ready to merge at <short sha>` (no final report yet).

## Phase 6: Merge and clean up
1. Merge the PR yourself, without waiting for a human, once every condition under "Merging" in the tracker skill holds (`scripts/check.sh --full` on the final head, CI green on that sha, mergeable). If one can't be met, post a `BLOCKED:` comment and stop; the final report then says BLOCKED.
2. Write the final report (below), with the merge commit sha. Post it as a comment on the merged PR (`gh pr comment <pr> --body-file -`) *before* cleanup, since cleanup removes your worktree.
3. Follow Landing a change, step 4, in the tracker skill, last: the one chained command that updates the root's `main`, removes this raft's worktree and deletes the local branch (it removes your own working directory, so nothing runs after it). Post no further commits to the branch. Then give the same report in your reply.

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
3. Leave the PR in **draft**, or, if it's already ready (a `BLOCKED:` stop after `done`), leave it as it is and unmerged.
4. Post a PR comment that starts with `BLOCKED:` and covers what you tried, the evidence, and the decision you need.

## Final report format
```
R0010: <title>. <MERGED | BLOCKED>
PR: <url>
Merge: <merge commit sha> | not merged: <which condition failed>
Cleanup: done | <what was skipped and why> (if this only becomes known after the report is posted, add a follow-up PR comment)
Criteria: <n>/<n> Checked PASS (tracker.sh done output), Judged: <rulings>
Observed (human, in Studio): <numbered steps from the issues' Observed sections>
Deviations: <issue: what and why> | none
Emergent issues: <ids and one line each> | none
Follow-ups filed: <ids> | none
Spend: <raft spend.md totals>
```
