---
name: execute-raft
description: The autonomous execution protocol for one raft - one branch, one PR, experiments first, tests first, spend-tracked commits, adversarial code review, done. Use when implementing a raft (or when handed a prompt by launch-raft or ready-raft).
---

# Execute a raft

Input: a raft ID (`R0010`) whose issues are `design: ready`.
Output: one PR, taken out of draft by `scripts/tracker.sh done R0010`, then merged by you (Phase 6).

Work through the phases in order and don't skip any. Wherever you are unsure, the tracker, architecture and testing skills are binding.

## Phase 0: Claim (in the first minutes)
1. Work in the raft's worktree: `cd "$(scripts/tracker.sh worktree R0010)"` (tracker skill, Worktrees), then run `scripts/tracker.sh sync` there (a reused worktree may be behind). A new worktree branches from a freshly fetched `origin/main`. Never switch branches in the main checkout, and run everything below from this directory. Confirm `scripts/check.sh --full` passes here.
   - **If main is red, stop.** Report it; don't fix main inside this raft.
2. `scripts/tracker.sh start R0010`. The claim was made by ready-raft: the raft and its members are already in `active/` on `origin/main`, so `start` only creates the branch (if the worktree isn't already on it), makes an empty `tracker: start` commit, pushes, and opens a **draft** PR. If it refuses with `run tracker.sh sync first`, sync and retry. A raft that was never readied (a legacy start) is claimed and moved by `start` itself; if a step after that claim fails, see the tracker skill, Sync and claim, A failed start.
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

## Phase 2B: Parallel workstreams (instead of Phase 2, when the plan allows it)
Use this when `scripts/tracker.sh workstreams <R-id>` ends with `parallel: yes` (the prompt embeds the plan) and the human hasn't asked for sequential execution. Otherwise run Phase 2 as written (Phase 2A). You are the **lead**: you alone push, merge, comment on the PR, allocate ids, and run `tracker.sh commit`, `focus` and `done`. The rest of this phase uses subagents; they can't spawn others, so you start every one of them.

1. **Plan.** Run `scripts/tracker.sh workstreams <R-id>`, post it as a PR comment, and execute **wave by wave**. A stream is one issue; the issues in a wave don't depend on each other and don't share files.
2. **Start a wave.** For every issue in the wave, create its worktree from the raft branch: `scripts/tracker.sh worktree ws-<issue> --from <raft branch>`. Then spawn one **Sonnet** subagent per stream (Agent tool, `model: "sonnet"`), **all in one message so the streams run concurrently**. Each brief contains:
   - the raft and issue ids, and the absolute path of the stream worktree ("your shell doesn't keep a working directory: start every command with `cd <path> &&` or use `git -C <path>`");
   - the issue document, its `check.sh` and its acceptance specs (paths; all sequestered), and the architecture, testing and tracker skills to follow;
   - the rules: tests first, implement the Design exactly, edit only the issue's Touched modules and its own Verification log, never edit `check.sh`, acceptance specs or `tracker/architecture.md`; never push, never comment on the PR, and never run `tracker.sh new`, `focus`, `commit`, `renumber`, `migrate` or `done` (you allocate ids and commit on the raft branch, so a problem the stream finds that no issue covers goes in its final report, and you file it); never create a `stream-review-*` or `stream-refute-*` file (the reviewer returns the review text and writes no file; the lead writes both files on the raft branch); commit implementation with plain `git add -A && git commit -m "<issue>: <what>"`; run `scripts/check.sh --affected` and `scripts/tracker.sh check <issue>` in the worktree; on a stop condition, stop and report instead of improvising;
   - what to report: `done` or `blocked`, the final commit sha, the minutes worked, deviations, and anything another issue needs.
3. **Review each stream** as soon as it reports `done`: a clean **Sonnet** subagent (`model: "sonnet"`) using the review skill's **Stream mode**. Its inputs are `git diff <raft branch>...ws-<issue>`, the issue document, `check.sh` and acceptance specs, and from round 2 the previous review and refute text (put that text in the brief; it is not in the stream tree). It runs the stream's checks, checks that the diff stays inside the issue's Touched modules and its own document, and returns the review markdown. It writes no file. You write `tracker/rafts/active/<R-id>/stream-review-<issue>-NNN.md` only in the raft worktree and, while that file is the only dirty path, record the reviewer: `scripts/tracker.sh commit -m "<issue>: stream-review-NNN" --phase code-review --time <reviewer minutes> --tokens <reviewer tokens> --issue <issue>` (omit `--tokens` when the report has none). That commit is the file plus its spend row. `commit` runs `git add -A`, so this happens before `git merge --squash`, never while a squash is staged, and never while any other path is dirty. The stream's author (continue the same subagent with SendMessage) returns the fix commits and the refute text, and writes no file. You write `stream-refute-<issue>-NNN.md` only in the raft worktree and commit it the same way, with `--time <answering minutes>` and `--issue <issue>`, again while that file is the only dirty path. **At most 2 rounds per stream**; a high finding still standing after round 2 means you take that issue over or escalate.
4. **Merge the stream.** In the raft worktree run `git merge --squash ws-<issue>`, then `scripts/tracker.sh commit -m "<issue>: <what the stream did>" --issue <issue> --time <stream minutes>`. Leave this commit on the default build phase: do not pass `--phase`. Squashing stages exactly the stream's net change, so the spend lines go to that issue, and the stream's own commits stay out of the raft history.
   - **If the squash conflicts** (two streams touched one file outside their declared modules), resolve it in the raft worktree, note it in both issues' Verification logs, rerun both issues' checks, and only then run `tracker.sh commit`, which refuses while unmerged paths remain.
   - Run `scripts/tracker.sh check <issue>`, then remove the stream's worktree and branch only when `git -C <stream> status --porcelain` is empty (an untracked file makes `worktree remove` refuse): `git -C <root> worktree remove <path> && git -C <root> branch -D ws-<issue>`. Comment on the PR: the review verdict and findings by severity, and the merge sha.
5. **Next wave.** Its streams start from the raft branch after the previous wave's merges. A blocked or unresolved stream is finished by you in the raft worktree (Phase 2A for that issue); say so in the Verification log, and remove its worktree and branch with the same command as in step 4, or a later `worktree ws-<issue> --from …` would silently resume the stale branch.
6. **Integrate.** After the last wave, **evaluate the acceptance criteria**: run `scripts/tracker.sh check <issue>` for every member issue and the raft's own `check.sh`. Make any last-minute changes yourself (small, committed with `tracker.sh commit`, each noted in the affected issue's Verification log). Then run Phase 3, and **Phase 4, the adversarial review of the sum total, on Opus**, exactly as written.
7. **Model policy.** Stream implementers and stream reviewers run on Sonnet (`model: "sonnet"`). The Phase 4 reviewer still runs on Opus (`model: "opus"`): stream reviews are a cheap first filter and never substitute for it. They aren't review rounds (`tracker.sh done` and `metrics` ignore `stream-review-*` and `stream-refute-*` files), and their findings need no answers for `done`.
8. **Final report.** Add one line per issue: `Workstreams: <issue>: <stream review verdict> | sequential`.

## Phase 3: Whole-raft verification
When the steps below pass, post a PR comment with the RC results.

1. `bash "$(scripts/tracker.sh find R0010)/check.sh"`. Every RC line must PASS.
2. Double-check that `scripts/check.sh --full` passes as well, and that `scripts/tracker.sh promote-check R0010` passes. It dry-runs the move of the acceptance specs into `tests/`. If it fails because of a sequestered spec, stop and escalate now, not at `done`.
3. **Gate speed**: record the **gate wall time** and the `slowest:` specs from a `scripts/check.sh --full` run in each issue's Verification log. If a stage or spec dominates or the time regressed, fix it or file the chore, per the testing skill's Speed section.
4. **Sequestration check**: `git fetch origin main && git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` must list nothing except `R100` renames (a raft started the legacy way moves its items on the branch). The three-dot form separates what this branch changed from what `main` brought in, so other terminals' new stubs are not false positives.

## Phase 4: Adversarial code review (a clean reviewer)
The PR is the visible record of the work. Push and post a PR comment (`gh pr comment --body-file -`) at each step below, so a human watching sees the review start, its findings, and how they were answered. Never hold review state locally. If a push or `gh` call fails, retry once, then carry on and mention the failure in your next comment; don't block on it. `tracker.sh commit` skips the push when there is no upstream, so check that `git status -sb` shows no `ahead`.

1. **Before launching**: commit any pending work with `tracker.sh commit` so the reviewer sees exactly what the PR shows. Run `scripts/check.sh --full` and read the whole lint summary (the `errors`/`warnings` lines, never just the last line); a red gate is fixed before a reviewer is launched. Then post the comment `Review NNN started at <short sha> (code mode)`.
2. Start a **clean** reviewer. It has none of your context and gets only these inputs:
   - the `review` skill (code mode);
   - `git fetch origin main && git diff origin/main...HEAD` (the local `main` isn't kept current);
   - the raft and issue documents and `check.sh` files;
   - read access to the repo.
   In Claude Code, that's a fresh subagent. For other agents, use a new session or context that receives only those inputs.
   Run the reviewer on **Opus 5.5**, even if you run on a cheaper model: a reviewer on the author's model shares its blind spots, and review is a small share of the spend. In Claude Code, pass `model: "opus"` to the Agent tool. Don't substitute another model, such as Fable or Sonnet. Outside Claude Code, use Opus 5.5 if the harness offers it; otherwise say which model reviewed in the review PR comment. Tell the reviewer to write only `review-NNN.md`: no commits, pushes, PR comments or stray files.
3. The reviewer writes `review-NNN.md` in the raft directory (starting at 001), including a ruling on every Judged criterion. **When the reviewer finishes**, you commit it: `scripts/tracker.sh commit -m "R0010: review-NNN" --phase code-review --time <reviewer minutes> --tokens <reviewer tokens>` (this pushes; both come from the reviewer's usage report, and leave `--tokens` out when the harness gives none). Then comment with the verdict and the finding count by severity, listing each `F<n> [severity] <claim>`.
4. **If the verdict is `approve` with no findings, go to Phase 5**: there is no refute file, and the verdict comment is the record. Otherwise respond in `refute-NNN.md`, with one line per finding:
   - `- F3: fixed <short sha>: <what changed>; consequences: <what the fix could break or open, and how you checked it, or none>`, or
   - `- F3: refuted: <argument with evidence>`, or
   - `- F3: deferred <id>: <why>`, only as step 7 allows (a medium or low finding left in the final round).
   Only refute when you can show the reviewer is wrong: a test, a spec, or the design text. Everything else gets fixed. Before each fix, take it one step further, as ticket-prep's consequence step does; `tracker.sh done` refuses a fixed answer without `consequences:`.
   4a. **Question a twice-hit mechanism.** When a finding is the second in two rounds against the same mechanism (the same guard, module or rule), stop patching. Before the next round, question the mechanism (a deny-list or an allowlist? a patch or a redesign?) and say which you chose, and why, in the refute file.
5. Commit each fix as you make it (pushed by `tracker.sh commit --phase code-review`), then commit the refute file the same way. Post a comment `Review NNN addressed`, pasting the refute file's lines.
6. **Re-review** after round 1 or 2 with `review-NNN+1.md` from a *new* clean reviewer if any of these are true (repeat from step 1); from round 3 on, step 7 decides instead:
   - any high-severity finding was fixed;
   - the fixes changed a public API or the design;
   - the fixes are more than about 15% of the PR's lines;
   - a Judged criterion was ruled fail;
   - you refuted (rather than fixed) any high finding or failed Judged criterion, so a new reviewer rules on the refutation.
7. **Cap: 5 rounds, prefer 3.** One rule decides, from the round's `review-NNN.md` severities and the diff of your answers. After round 1 or 2, step 6 decides. After round 3 or 4, run the next round only if that round was **major**: it had a **high** finding or a Judged criterion ruled fail, or answering it was more than minor. The **final round** is the round after which this rule runs no further round: any round 1 to 4 where it says stop, or round 5, which is always final. Minor means the answers changed only wording, labels, comments or single assertions, and added no rule, interface, state, spec case, Rules and mutants row or public API change, and the fixes stay under about 15% of the PR's lines.
   The reviewer's own file decides what is significant, not your answer to it. If the final round's `review-NNN.md` contains any **high** finding or any Judged criterion ruled fail, the merge is blocked and the human is engaged, whether or not you fixed it, because no reviewer remains to verify the fix or a refutation. Stop and escalate. (Rounds before the final one need no such rule: a fresh reviewer in the next round rules on every refutation.) Medium and low findings in the final round's `review-NNN.md` do not block, and you can't downgrade the severity the reviewer wrote. Fix them (answer `fixed`) if the fix is small; otherwise file each with `tracker.sh new issue`, answer it in the final round's `refute-NNN.md` as `- F<n>: deferred <id>: <why>` (`<id>` is the new backlog issue; `tracker.sh done` accepts it only for a medium or low finding), and quote every such line in the round's PR comment. A deferral is honest, not a refutation, so it is no exception to "only refute when the reviewer is wrong". Then continue to Phase 5.

## Phase 5: Done
1. Append each issue's final Verification log entry and fill in the raft's "Addressed during execution". Commit with `scripts/tracker.sh commit --phase deliver`.
2. `git fetch origin main` and merge it into the branch now (renumber colliding IDs, rerun `scripts/check.sh --full`, commit with `scripts/tracker.sh commit --phase deliver`), so the PR is up to date before `done` and nothing needs changing after it.
3. `scripts/tracker.sh done R0010`. It re-verifies everything, marks the PR ready, then moves the items to `done/` and pushes the done commit.
4. Post a PR comment `Ready to merge at <short sha>` (no final report yet).

## Phase 6: Merge and clean up
1. Merge the PR yourself, without waiting for a human, once every condition under "Merging" in the tracker skill holds (`scripts/check.sh --full` on the final head, CI green on that sha, mergeable). If one can't be met, post a `BLOCKED:` comment and stop; the final report then says BLOCKED.
2. After the merge and before the final report, `scripts/tracker.sh spend R0010 --phase deliver --time <minutes from done to merged>`.
3. Write the final report (below), with the merge commit sha. Post it as a comment on the merged PR (`gh pr comment <pr> --body-file -`) *before* cleanup, since cleanup removes your worktree.
4. Follow Landing a change, step 4, in the tracker skill, last: the one chained command that updates the root's `main` (`"<root>/scripts/tracker.sh" sync`, which also rebuilds its board), removes this raft's worktree and deletes the local branch (it removes your own working directory, so nothing runs after it). Post no further commits to the branch. Then give the same report in your reply.

## Stop conditions (escalate; don't improvise)
Stop and report if any of these happen:
- An experiment fails and has no fallback.
- The design is wrong beyond local adjustments.
- A `check.sh` or acceptance spec is wrong or can't be satisfied.
- Main is red.
- A tool is missing and `SETUP.md` doesn't fix it.
- The final round of review is still unresolved.
- An action would require a secret or credential you don't have.
- A test run prints `REPOSITORY CHANGED` or refuses a fixture identity, or the shared repository's remotes, branches, worktrees or identity look wrong: stop at once, and never repair the shared git configuration yourself (testing skill, "Specs never touch the real repository").

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
Workstreams: <issue>: <stream review verdict> | sequential   (one line per issue; only when Phase 2B was used)
```
