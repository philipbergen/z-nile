---
name: zz-execute
description: The execution protocol for one raft, followed from inside z-run (or from a raft's prompt) - one layer per ticket, experiments first, tests first, spend-tracked commits, adversarial code review, done. Use when executing a raft you were handed.
---

# Execute a raft

Input: a raft ID (`R0010`) whose issues are `design: ready`, readied by z-ready and launched by z-run (or handed to you as its prompt).
Output: one layer per ticket. `./zn finish <issue>` makes that layer one commit; `./zn done R0010` lands the stack.

Work through the phases in order and don't skip any. Wherever you are unsure, the zz-rules, zz-arch and zz-test skills, and your project's own skills (`pickman-arch` and `pickman-test` for pickman), are binding.

## Phase 0: Claim (in the first minutes)
1. Work in the raft's worktree: `cd "$(./zn worktree R0010)"` (zz-rules skill, Worktrees), then run `./zn sync` there (a reused worktree may be behind). A new raft worktree is detached at a freshly fetched `origin/main` until `./zn start` checks out the layer. There is no `R####-<slug>` branch. Never switch branches in the main checkout, and run everything below from this directory. Phase 0 runs no gate and reads no CI result: a red `main` first shows at the merge.
2. `./zn start R0010`. It opens the next layer (branch `R0010/1/c0010`, an empty commit, a draft PR on the layer below). You are on one ticket: this layer, the layer below, and this ticket's checks. `./zn finish <issue>` when they are green; `./zn start` again opens the next layer. If it refuses with `run ./zn sync first`, sync and retry.
3. Read the raft document, then every issue document and `check.sh`, in the raft's order.
   - Write down, for yourself, which files each issue touches.

## Phase 1: Experiments (fail fast)
- Run every probe, experiment, loop and background command you start yourself (anything that is not the gate, a check, a `./zn` command or the spec runner) through `./zn run --time <seconds> -- <command>`: it stops at its limit, when it ends and when you do. A `/clear` ends the background commands of the conversation it clears (the SessionEnd hook stops its tool shells).
- For every unknown in the raft's and issues' "Unknowns & experiments" that has no recorded result: run the experiment in the issue's `experiments/` directory, and record the result in the issue document.
- **If an experiment fails:**
  - Switch to the documented fallback, and note that in the issue.
  - If there's no fallback: **stop** and escalate (see Stop conditions).
- Commit: `./zn commit -m "R0010: experiments"`, then post a PR comment listing each experiment and its result. Do not pass `--time` or `--tokens`; the tool measures cost.

## Phase 2: Implement, one issue at a time in the raft's order
For each issue:
1. `./zn focus <issue>`.
2. **Tests first.**
   - Write the specs in the issue's Test plan under `tests/`. These are your own unit, contract and regression specs.
   - The sequestered acceptance specs in `<root>/issues/<id>/acceptance/` (`./zn find <id>`) already exist from prep. Don't modify or move them; `done` promotes them.
   - Run them and confirm that each one **fails for the expected reason**, not because of a syntax error or a missing file.
3. **Implement** the Design exactly, following the Implementation steps.
   - Iterate with `z-nile/check.sh --affected`.
   - Commit at meaningful green steps with `./zn commit -m "<issue>: <what>"`. Do not pass `--time` or `--tokens`.
4. **Finish the issue**: `./zn check <issue>` shows every AC as PASS. Append a Verification log entry, commit it, then `./zn finish <issue>`. That squashes this layer into one commit (`<issue>: <title>`). `./zn start` opens the next layer. Post a PR comment `<issue> done: n/n ACs PASS`.
5. **Deviations**:
   - If the design turns out to be wrong in a small, local way (for example a name or a helper split), adjust it and record the deviation, with the reason, in the issue's Verification log.
   - If it's wrong in a way that changes a public API, a cross-feature dependency or an acceptance criterion, **stop** and escalate.
6. **Emergent problems**: follow "Emergent issues" in the zz-rules skill. Only fix them now if they can't be postponed.

## Phase 2B: Parallel work
Layers replace stream branches. There is no `ws-<issue>` branch and nothing is squashed into a raft branch. One worker holds the raft and builds its layers one at a time, each complete before the next starts; a second machine works on the raft only through a takeover (c0274). `./zn stack <R-id>` shows where the stack stands. A layer may still be built by streams: subagents of the worker committing on the layer it is on. Commits on a layer, whoever made them, become that layer's one commit at `./zn finish <issue>`.

**Candidate lessons are written as they arrive**, on the layer, so finish folds them into that one commit. A subagent puts a candidate in its report: a candidate lesson goes in the final report too. The lead records `- note ws-<issue>: <lesson ids>` or `- note stream-review-<issue>-NNN: <lesson ids>` in the raft's `harvest.md` when a report arrives, and commits it on the layer.

1. Finish the layer you are on with `./zn finish <issue>` once its checks are green, then review it (Phase 4). `./zn start` opens the next layer only when this one is complete: finished, green and reviewed.
2. Review that layer in Code mode. The reviewer is given `git diff <layer below>...HEAD` (the first layer: `origin/main...HEAD`).
3. After a fix on a lower layer, `./zn finish` that layer again and `./zn restack <R-id>` before an upper layer is reviewed or `./zn done` lands the stack.

## Phase 3: Whole-raft verification
When the steps below pass, post a PR comment with the RC results.

1. `bash "$(./zn find R0010)/check.sh"`. Every RC line must PASS.
2. Double-check that `z-nile/check.sh --affected` passes as well (every project: the raft's RC0 runs only its own project's gate, c0120), and that `./zn promote-check R0010` passes. It dry-runs the move of the acceptance specs into the project's `tests/acceptance/`. If it fails because of a sequestered spec, stop and escalate now, not at `done`.
3. **Gate speed** moves to Phase 6 step 1: the wall time and the `slowest:` specs of the merge's full gate go in the final report and its PR comment, never into a tracked file.
4. **Sequestration check**: `git fetch origin main && git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` must list nothing except `R100` renames (a raft started the legacy way moves its items on the branch). The three-dot form separates what this branch changed from what `main` brought in, so other terminals' new stubs are not false positives.

## Phase 4: Adversarial code review (a clean reviewer)
Phase 4 runs per layer, after the layer's `./zn finish` and before the next `./zn start`. Its files are `review-NNN.md` and `refute-NNN.md` in the issue's folder (`<root>/issues/active/<id>/`), numbered from 001 per issue. The tool stamps them: `./zn commit` (or the dispatcher, for a dispatched review) writes `Commit: <sha>` and `Patch: <id>` on their first lines from the layer's finish commit, and a reviewer never writes them. A layer is complete when its newest review is settled and current: its stamp names the finish commit or the same patch (a clean restack keeps it), or its refute answers a finding `fixed` for the new commit. `./zn start` and `./zn done` refuse a layer that is not. A layer's open list (`## Open to the human`) is the issue document's, and its harvest is the issue folder's `harvest.md`. A review with `Verdict: approve` and no findings goes to the next layer with nothing more to answer. A review file an old raft keeps in the raft folder still parses.

The PR is the visible record of the work. Push and post a PR comment (`gh pr comment --body-file -`) at each step below, so a human watching sees the review start, its findings, and how they were answered. Never hold review state locally. If a push or `gh` call fails, retry once, then carry on and mention the failure in your next comment; don't block on it. `./zn commit` skips the push when there is no upstream, so check that `git status -sb` shows no `ahead`.

1. **Before launching**: commit any pending work with `./zn commit` so the reviewer sees exactly what the PR shows. Run `z-nile/check.sh --affected` and read the whole lint summary (the `errors`/`warnings` lines, never just the last line); a red gate is fixed before a reviewer is launched. Then post the comment `Review NNN started at <short sha> (code mode)`.
2. Start a **clean** reviewer. It has none of your context and gets only these inputs:
   - the `zz-review` skill (code mode);
   - `git diff <layer below>...HEAD` (the first layer: `origin/main...HEAD`; the local `main` isn't kept current);
   - the raft and issue documents and `check.sh` files;
   - read access to the repo.
   In Claude Code, that's a fresh subagent. For other agents, use a new session or context that receives only those inputs.
   Run the reviewer on the **code-review role** `.models.toml` names, never on the model that wrote the code. `./zn dispatch zz-review <R-id> --mode code` starts it on that role and prints the `./zn commit … --phase code-review --model <id>` line for step 3 (a headless run always uses it). In an interactive session, start the reviewer subagent on that role's model. Say which model reviewed in the review PR comment. Tell a subagent reviewer to write only `review-NNN.md`: no commits, pushes, PR comments or stray files (a dispatched one writes `review.md` in its state folder, and the dispatcher places it as `review-NNN.md`).
3. The reviewer writes `review-NNN.md` in the issue's folder (starting at 001; the tool stamps it), including a ruling on every Judged criterion. **When the reviewer finishes**, you commit it on the layer: `./zn commit -m "c0010: review-NNN" --phase code-review --model <reviewer model>` (this pushes; the model comes from the one `record:` line `./zn dispatch zz-review` printed. Do not pass `--time` or `--tokens`). Then comment with the verdict and the finding count by severity, listing each `F<n> [severity] <claim>`. A dispatched review that fails with "the reviewer wrote no review" still prints its `record:` line: commit that line alone (the commit is its spend row), then rerun the review, which is still the same round.
4. **If the verdict is `approve` with no findings, go to Phase 5**: there is no refute file, and the verdict comment is the record. Otherwise respond in `refute-NNN.md`, with one line per finding:
   - `- F3: fixed <short sha>: <what changed>; consequences: <what the fix could break or open, and how you checked it, or none>`, or
   - `- F3: refuted: <argument with evidence>`, or
   - `- F3: deferred <id>: <why>`, only for a medium or low finding (a high cannot be deferred).
   Only refute when you can show the reviewer is wrong: a test, a spec, or the design text. Everything else gets fixed. Before each fix, take it one step further, as z-design's consequence step does; `./zn done` refuses a fixed answer without `consequences:`.
5. Commit each fix as you make it (pushed by `./zn commit --phase code-review`). **Harvest the round** as z-design step 5.3 does: one entry per finding of `review-NNN.md` in the raft's `harvest.md` (any lesson, design ones included; a new one is usually `when: build` or `both`), then `./zn lessons --uncovered R0010` and `./zn lessons --check`. Then commit the refute file, the ledger and the lessons the same way. Post a comment `Review NNN addressed`, pasting the refute file's lines.
6. **Then the human.** There is no second reviewer. After this one revision, anything you refuted, any high finding you could not close (not answered `fixed`), and any Judged criterion ruled fail, goes in the issue document under `## Open to the human` (a final review's, in the raft document), one bullet each: `- F2: <the finding>. Answer: <your answer>. Decision: <what the human must decide>` (a failed Judged criterion uses its `JC<n>` id). The raft can be `done` when that list is empty or every bullet carries `Ruled (user, YYYY-MM-DD): <their decision>`. Do not guess a ruling. A medium or low finding you fixed, or deferred to a backlog issue (`- F<n>: deferred <id>: <why>`; `./zn done` accepts that only for a medium or low finding), does not go on the list. Quote every deferred line in the PR comment. Then continue to Phase 5.

## Phase 5: Done
1. Append each issue's final Verification log entry and fill in the raft's "Addressed during execution". Commit with `./zn commit --phase deliver`.
2. If `main` moved, `./zn restack <R-id>` (renumber colliding IDs, rerun `z-nile/check.sh --affected`, commit with `./zn commit --phase deliver`), so the stack is on that main before `done`.
3. **Final review (idea = design = test = code)**, once per bind: after the last layer the bind lands is finished and restacked, print the trace skeleton with `./zn trace <R-id>` (`./zn trace <R-id> --through <issue>` for a shorter bind), and run the final review once on those layers (`./zn dispatch zz-review <R-id> --mode final`, or a fresh subagent on the review model of the CLI in final mode) given the skeleton, the tickets' documents and `git diff origin/main...HEAD`. The reviewer fills `<raft-dir>/trace-NNN.md` and writes `final-review-NNN.md` (NNN is one more than the highest final review on `origin/main`: each landing has its own) with a verdict and findings. Answer any findings once in `final-refute-NNN.md` (if a fix changes a layer, `./zn finish` and `./zn restack <R-id>`, and update `trace-NNN.md` for the new top-layer commit; anything still open goes under `## Open to the human`). Verify `./zn trace <R-id> [--through <issue>] --check` passes and commit `trace-NNN.md` and the final review files with `./zn commit --phase code-review --model <reviewer model>`.
4. **Confirm the harvest**: first harvest anything `./zn lessons --uncovered R0010` still lists, as Phase 4 step 5 says. That includes the design reviews of a raft prepped before lessons existed, which are harvested here by you. Then `./zn lessons --uncovered R0010` and `./zn lessons --check` must pass. Commit with `./zn commit --phase deliver`.
5. `./zn done R0010` lands the stack. It refuses a checkout that is not the published top-layer commit, an unfinished or unstacked layer, a changed contract, a failing or stale `./zn trace <R-id> --check`, and a final review with no `Verdict:` line or whose verdict is not `approve` while an open finding has no human ruling in `## Open to the human`. The binding commit records the final review's `Verdict:` line and `Trace: <raft-dir>/trace-NNN.md`, the file of this landing. The human runs `./zn approve <id>` again when the contract changed, then `./zn done`.
6. Run the final review and `./zn done` once per landing. When a layer is blocked, the green layers below it land now: `./zn done R0010 --through <issue>` lands only the layers up to that issue's, after its own final review (`final-review-NNN.md`) and trace (`trace-NNN.md`) over exactly those layers. It moves only those tickets to `done/`, and the raft stays in `active/` until its last layer lands. The raft's `check.sh` runs for the landing's members (`ZN_BIND_MEMBERS`), and its `RC1` and later lines run at the last landing. After an early landing run `./zn restack R0010`: the lowest layer left is based on `main`, and its review stays current by its patch. The layer after them resumes once the blocker is resolved.
7. Post a PR comment `Ready to merge at <short sha>` (no final report yet).

## Phase 6: Merge and clean up
Under `./zn dispatch` (headless) the run ends at Phase 5's `Ready to merge` comment: the merge of the run's PR is a human's gate, and the dispatcher records the run's spend after it. Skip this phase.
1. `./zn done` already landed the stack (one `--no-ff` merge). Do not merge again and do not squash. After the merge, `./zn watch-kick`: it returns at once, starts the net under `./zn run`, and writes `.cache/watch-net.log` in that checkout. It does not delay the merge, and a failure there does not fail it. A pull request that changes only tooling is gated by `z-nile/check.sh --affected` on the branch. A pull request that changes a game is gated by the local full gate, `z-nile/check.sh --full`, in a clone of the exact head whose parent directories are not a checkout of this repo, and by `lune run scripts/cicd` there. The PR is mergeable. Record the **gate wall time** and the `slowest:` specs of the merge's gate in the final report and its PR comment. If the merge's gate fails, post a `BLOCKED:` comment naming the failing specs and stop with the PR ready and unmerged; in the raft worktree at the PR head, for each failing spec that `lune run z-nile/affected -- --base $(git merge-base origin/main HEAD)` does not list, file a watch-miss chore (zz-test, Watch miss) and say so in the comment, unless the spec also fails on `origin/main` (then it is a red `main`: say that instead). If another condition can't be met, post a `BLOCKED:` comment and stop; the final report then says BLOCKED. A re-run after main moves is required only when the merged-in commits select a spec for this pull request; tracker-only commits require none (zz-rules, Merging).
2. After the merge and before the final report, `./zn spend R0010 --phase deliver`. Do not pass `--time` or `--tokens`.
3. Write the final report (below), with the merge commit sha. Post it as a comment on the merged PR (`gh pr comment <pr> --body-file -`) *before* cleanup, since cleanup removes your worktree.
4. Follow Landing a change, step 4, in the zz-rules skill, last: the one chained command that updates the root's `main` (`"<root>/zn" sync`, which also rebuilds its board), removes this raft's worktree and deletes the local branch (it removes your own working directory, so nothing runs after it). Post no further commits to the branch. Then give the same report in your reply.

## Stop conditions (escalate; don't improvise)
Stop and report if any of these happen:
- An experiment fails and has no fallback.
- The design is wrong beyond local adjustments.
- Delivering an issue would drop or shrink an outcome its Problem asks for, because the design, a check or a fix requires it. Only the user changes scope.
- A `check.sh` or acceptance spec is wrong or can't be satisfied.
- Main is red.
- A tool is missing and `SETUP.md` doesn't fix it.
- The open list under `## Open to the human` still has a bullet with no `Ruled (user, YYYY-MM-DD):`.
- An action would require a secret or credential you don't have.
- A test run prints `REPOSITORY CHANGED` or refuses a fixture identity, or the shared repository's remotes, branches, worktrees or identity look wrong: stop at once, and never repair the shared git configuration yourself (zz-test skill, "Specs never touch the real repository").

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
Criteria: <n>/<n> Checked PASS (./zn done output), Judged: <rulings>
Observed (human, in Studio): <numbered steps from the issues' Observed sections>
Deviations: <issue: what and why> | none
Emergent issues: <ids and one line each> | none
Follow-ups filed: <ids> | none
Spend: <raft spend.md totals>
Workstreams: <issue>: <stream review verdict> | sequential   (one line per issue; only when Phase 2B was used)
```

## Lessons
Search with `./zn lessons <terms>` when you are about to do something a lesson might cover.

A new lesson (from a review finding, a correction by the user, or a step that failed in a way a rule would have prevented) is handled by your role, not by the skill you are reading:
- **A subagent** (a stream, a reviewer, any agent working from a brief) never writes a lesson file or runs `./zn new`. It puts the candidate (the rule, why, and the question that catches it) in its review or final report.
- **The lead of a prep or raft** writes it in `<skills folder>/<the skill the lesson improves>/lessons/<slug>.md` (the real folder: `z-nile/skills/` for z-nile's skills, `<project>/skills/` for a project's, never through a `.claude/skills/` link, which git can't add through; format: zz-rules skill, Items), and records where it came from in its own `harvest.md`: review findings through the harvest (z-design step 5.3, zz-execute Phase 4 step 5), and anything else (a subagent's candidate, a correction by the user, a failed step) as `- note <what happened>: <lesson ids>`. It adds a note to an existing lesson when one fits, writes a new file only when none does, and commits both with its work.
- **Any other lead** (in the main checkout, a capture, or a metrics report) captures it: `./zn new issue c lesson-<slug> --project z-nile --desc "<skill>: <the rule>, because <what happened>; check: <the question>"` (z-ticket skill). The prep that takes the issue writes the file.
