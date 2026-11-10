---
name: zz-execute
description: The execution protocol for one raft, followed from inside z-run (or from a raft's prompt) - one branch, one PR, experiments first, tests first, spend-tracked commits, adversarial code review, done. Use when executing a raft you were handed.
---

# Execute a raft

Input: a raft ID (`R0010`) whose issues are `design: ready`, readied by z-ready and launched by z-run (or handed to you as its prompt).
Output: one PR, taken out of draft by `./zn done R0010`, then merged by you (Phase 6).

Work through the phases in order and don't skip any. Wherever you are unsure, the zz-rules, zz-arch and zz-test skills, and your project's own skills (`pickman-arch` and `pickman-test` for pickman), are binding.

## Phase 0: Claim (in the first minutes)
1. Work in the raft's worktree: `cd "$(./zn worktree R0010)"` (zz-rules skill, Worktrees), then run `./zn sync` there (a reused worktree may be behind). A new worktree branches from a freshly fetched `origin/main`. Never switch branches in the main checkout, and run everything below from this directory. Phase 0 runs no gate and reads no CI result: a red `main` first shows at the merge.
2. `./zn start R0010`. The claim was made by z-ready: the raft and its members are already in `active/` on `origin/main`, so `start` only creates the branch (if the worktree isn't already on it), makes an empty `tracker: start` commit, pushes, and opens a **draft** PR. If it refuses with `run ./zn sync first`, sync and retry. A raft that was never readied (a legacy start) is claimed and moved by `start` itself; if a step after that claim fails, see the zz-rules skill, Sync and claim, A failed start.
3. Read the raft document, then every issue document and `check.sh`, in the raft's order.
   - Write down, for yourself, which files each issue touches.

## Phase 1: Experiments (fail fast)
- Run every probe, experiment, loop and background command you start yourself (anything that is not the gate, a check, a `./zn` command or the spec runner) through `./zn run --time <seconds> -- <command>`: it stops at its limit, when it ends and when you do. A `/clear` ends the background commands of the conversation it clears (the SessionEnd hook stops its tool shells).
- For every unknown in the raft's and issues' "Unknowns & experiments" that has no recorded result: run the experiment in the issue's `experiments/` directory, and record the result in the issue document.
- **If an experiment fails:**
  - Switch to the documented fallback, and note that in the issue.
  - If there's no fallback: **stop** and escalate (see Stop conditions).
- Commit: `./zn commit -m "R0010: experiments" --time <minutes>`, then post a PR comment listing each experiment and its result.

## Phase 2: Implement, one issue at a time in the raft's order
For each issue:
1. `./zn focus <issue>`.
2. **Tests first.**
   - Write the specs in the issue's Test plan under `tests/`. These are your own unit, contract and regression specs.
   - The sequestered acceptance specs in `<root>/issues/<id>/acceptance/` (`./zn find <id>`) already exist from prep. Don't modify or move them; `done` promotes them.
   - Run them and confirm that each one **fails for the expected reason**, not because of a syntax error or a missing file.
3. **Implement** the Design exactly, following the Implementation steps.
   - Iterate with `z-nile/check.sh --affected`.
   - Commit at meaningful green steps with `./zn commit -m "<issue>: <what>"`, adding `--time` when you know it.
4. **Finish the issue**: `./zn check <issue>` shows every AC as PASS. Then append a Verification log entry to the issue document, commit, and post a PR comment `<issue> done: n/n ACs PASS`.
5. **Deviations**:
   - If the design turns out to be wrong in a small, local way (for example a name or a helper split), adjust it and record the deviation, with the reason, in the issue's Verification log.
   - If it's wrong in a way that changes a public API, a cross-feature dependency or an acceptance criterion, **stop** and escalate.
6. **Emergent problems**: follow "Emergent issues" in the zz-rules skill. Only fix them now if they can't be postponed.

## Phase 2B: Parallel workstreams (instead of Phase 2, when the plan allows it)
Use this when `./zn workstreams <R-id>` ends with `parallel: yes` (the prompt embeds the plan) and the human hasn't asked for sequential execution. Otherwise run Phase 2 as written (Phase 2A). You are the **lead**: you alone push, merge, comment on the PR, allocate ids, and run `./zn commit`, `focus` and `done`. The rest of this phase uses subagents; they can't spawn others, so you start every one of them.

**Candidate lessons are written as they arrive**, so no path (an approving review, a blocked or taken-over stream) can drop them. Each time a stream's report reaches you (done or blocked), and each time you commit a `stream-review-<issue>-NNN.md`, write the candidate lessons it holds as `- note ws-<issue>: <lesson ids>` (from a report) or `- note stream-review-<issue>-NNN: <lesson ids>` (from a stream review) in the raft's `harvest.md`, with a new lesson file only when no lesson fits. Commit them on their own: `./zn commit -m "<issue>: lessons" --phase code-review --issue <issue>`.

1. **Plan.** Run `./zn workstreams <R-id>`, post it as a PR comment, and execute **wave by wave**. A stream is one issue; the issues in a wave don't depend on each other and don't share files.
2. **Start a wave.** For every issue in the wave, create its worktree from the raft branch: `./zn worktree ws-<issue> --from <raft branch>`. Then spawn one **Sonnet** subagent per stream (Agent tool, `model: "sonnet"`), **all in one message so the streams run concurrently**. Each brief contains:
   - the raft and issue ids, and the absolute path of the stream worktree ("your shell doesn't keep a working directory: start every command with `cd <path> &&` or use `git -C <path>`");
   - the issue document, its `check.sh` and its acceptance specs (paths; all sequestered), and the zz-rules, zz-arch and zz-test skills and the project's own skills to follow;
   - the rules: tests first, implement the Design exactly, edit only the issue's Touched modules and its own Verification log, never edit `check.sh`, acceptance specs or the project's `architecture.md` (`pickman/.tracker/architecture.md`); never push, never comment on the PR, and never run `./zn new`, `focus`, `commit`, `renumber`, `migrate` or `done` (you allocate ids and commit on the raft branch, so a problem the stream finds that no issue covers goes in its final report, and you file it; a candidate lesson goes in the final report too, and you harvest it); never create a `stream-review-*` or `stream-refute-*` file (an interactive reviewer returns its text and the lead writes the file; a dispatched one's review is placed in the raft worktree by the dispatcher; the lead commits both there); commit implementation with plain `git add -A && git commit -m "<issue>: <what>"`; run `z-nile/check.sh --affected` and `./zn check <issue>` in the worktree; on a stop condition, stop and report instead of improvising;
   - what to report: `done` or `blocked`, the final commit sha, the minutes worked, deviations, anything another issue needs, and candidate lessons (the rule, why, and the question that catches it).
3. **Review each stream** as soon as it reports `done`. In an interactive session: a clean **Sonnet** subagent (`model: "sonnet"`) using the zz-review skill's **Stream mode**. Its inputs are `git diff <raft branch>...ws-<issue>`, the issue document, `check.sh` and acceptance specs. One round: there is no second stream review. It runs the stream's checks, checks that the diff stays inside the issue's Touched modules and its own document, and returns the review markdown. It writes no file. You write `tracker/rafts/active/<R-id>/stream-review-<issue>-NNN.md` only in the raft worktree and, while that file is the only dirty path, record the reviewer: `./zn commit -m "<issue>: stream-review-NNN" --phase code-review --time <reviewer minutes> --tokens <reviewer tokens> --issue <issue>` (omit `--tokens` when the report has none). That commit is the file plus its spend row. `commit` runs `git add -A`, so this happens before `git merge --squash`, never while a squash is staged, and never while any other path is dirty. The stream's author (continue the same subagent with SendMessage) returns the fix commits and the refute text, and writes no file. You write `stream-refute-<issue>-NNN.md` only in the raft worktree and commit it the same way, with `--time <answering minutes>` and `--issue <issue>`, again while that file is the only dirty path. Under the dispatcher, step 7 replaces the subagent. **At most 2 rounds per stream**; a high finding still standing after round 2 means you take that issue over or escalate.
4. **Merge the stream.** In the raft worktree run `git merge --squash ws-<issue>`. Then `./zn commit -m "<issue>: <what the stream did>" --issue <issue> --time <stream minutes>`. Leave this commit on the default build phase: do not pass `--phase`. Squashing stages exactly the stream's net change, so the spend lines go to that issue, and the stream's own commits stay out of the raft history.
   - **If the squash conflicts** (two streams touched one file outside their declared modules), resolve it in the raft worktree, note it in both issues' Verification logs, rerun both issues' checks, and only then run `./zn commit`, which refuses while unmerged paths remain.
   - Run `./zn check <issue>`, then remove the stream's worktree and branch only when `git -C <stream> status --porcelain` is empty (an untracked file makes `worktree remove` refuse): `git -C <root> worktree remove <path> && git -C <root> branch -D ws-<issue>`. Comment on the PR: the review verdict and findings by severity, and the merge sha.
5. **Next wave.** Its streams start from the raft branch after the previous wave's merges. A blocked or unresolved stream is finished by you in the raft worktree (Phase 2A for that issue); say so in the Verification log, and remove its worktree and branch with the same command as in step 4, or a later `worktree ws-<issue> --from …` would silently resume the stale branch.
6. **Integrate.** After the last wave, **evaluate the acceptance criteria**: run `./zn check <issue>` for every member issue and the raft's own `check.sh`. Make any last-minute changes yourself (small, committed with `./zn commit`, each noted in the affected issue's Verification log). Then run Phase 3, and **Phase 4, the adversarial review of the sum total, on the review model of the CLI**, exactly as written.
7. **Model policy.** Stream implementers and stream reviewers run on Sonnet (`model: "sonnet"`). Under the dispatcher, on any CLI, a stream review is `./zn dispatch zz-review <issue> --mode stream` instead (the review model of the CLI; the dispatcher places the review as `stream-review-<issue>-NNN.md` in the raft's folder, and you commit it with the `record:` line it prints (`-m "<issue>: stream-review-NNN"` … `--issue <issue>`), while that file is the only dirty path), and a CLI with no subagents runs the streams one after another (Phase 2A). One dispatched stream review at a time: commit its file before you start the next. A dispatched stream review that fails with no review is handled as Phase 4 step 3 says. The Phase 4 reviewer still runs on the review model of the CLI (Phase 4): stream reviews are a cheap first filter and never substitute for it. They aren't review rounds (`./zn done` and `metrics` ignore `stream-review-*` and `stream-refute-*` files), and their findings need no answers for `done`.
8. **Final report.** Add one line per issue: `Workstreams: <issue>: <stream review verdict> | sequential`.

## Phase 3: Whole-raft verification
When the steps below pass, post a PR comment with the RC results.

1. `bash "$(./zn find R0010)/check.sh"`. Every RC line must PASS.
2. Double-check that `z-nile/check.sh --affected` passes as well (every project: the raft's RC0 runs only its own project's gate, c0120), and that `./zn promote-check R0010` passes. It dry-runs the move of the acceptance specs into the project's `tests/acceptance/`. If it fails because of a sequestered spec, stop and escalate now, not at `done`.
3. **Gate speed** moves to Phase 6 step 1: the wall time and the `slowest:` specs of the merge's full gate go in the final report and its PR comment, never into a tracked file.
4. **Sequestration check**: `git fetch origin main && git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**' '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` must list nothing except `R100` renames (a raft started the legacy way moves its items on the branch). The three-dot form separates what this branch changed from what `main` brought in, so other terminals' new stubs are not false positives.

## Phase 4: Adversarial code review (a clean reviewer)
The PR is the visible record of the work. Push and post a PR comment (`gh pr comment --body-file -`) at each step below, so a human watching sees the review start, its findings, and how they were answered. Never hold review state locally. If a push or `gh` call fails, retry once, then carry on and mention the failure in your next comment; don't block on it. `./zn commit` skips the push when there is no upstream, so check that `git status -sb` shows no `ahead`.

1. **Before launching**: commit any pending work with `./zn commit` so the reviewer sees exactly what the PR shows. Run `z-nile/check.sh --affected` and read the whole lint summary (the `errors`/`warnings` lines, never just the last line); a red gate is fixed before a reviewer is launched. Then post the comment `Review NNN started at <short sha> (code mode)`.
2. Start a **clean** reviewer. It has none of your context and gets only these inputs:
   - the `zz-review` skill (code mode);
   - `git fetch origin main && git diff origin/main...HEAD` (the local `main` isn't kept current);
   - the raft and issue documents and `check.sh` files;
   - read access to the repo.
   In Claude Code, that's a fresh subagent. For other agents, use a new session or context that receives only those inputs.
   Run the reviewer on the **review model of the CLI** (the user's rule): Opus through `claude` or `agent`, any grok model at `xhigh` through `grok`, whatever model the author runs on: a reviewer on the author's model shares its blind spots, and review is a small share of the spend. `./zn dispatch zz-review <R-id> --mode code` starts it on the CLI and model `.models.toml` names for `zz-review` and prints the `./zn commit … --tokens <n> --model <id>` line for step 3 (a headless run always uses it). In an interactive Claude Code session you may instead pass `model: "opus"` to the Agent tool; don't substitute another model, such as Fable or Sonnet. Say which model reviewed in the review PR comment. Tell a subagent reviewer to write only `review-NNN.md`: no commits, pushes, PR comments or stray files (a dispatched one writes `review.md` in its state folder, and the dispatcher places it as `review-NNN.md`).
3. The reviewer writes `review-NNN.md` in the raft directory (starting at 001), including a ruling on every Judged criterion. **When the reviewer finishes**, you commit it: `./zn commit -m "R0010: review-NNN" --phase code-review --time <reviewer minutes> --tokens <reviewer tokens> --model <reviewer model>` (this pushes; all three come from the one `record:` line `./zn dispatch zz-review` printed (one line even after a quota fallthrough: the attempts summed under the reviewing model), or from a subagent's usage report, and leave `--tokens` out when the harness gives none). Then comment with the verdict and the finding count by severity, listing each `F<n> [severity] <claim>`. A dispatched review that fails with "the reviewer wrote no review" still prints its `record:` line: commit that line alone (the commit is its spend row), then rerun the review, which is still the same round.
4. **If the verdict is `approve` with no findings, go to Phase 5**: there is no refute file, and the verdict comment is the record. Otherwise respond in `refute-NNN.md`, with one line per finding:
   - `- F3: fixed <short sha>: <what changed>; consequences: <what the fix could break or open, and how you checked it, or none>`, or
   - `- F3: refuted: <argument with evidence>`, or
   - `- F3: deferred <id>: <why>`, only for a medium or low finding (a high cannot be deferred).
   Only refute when you can show the reviewer is wrong: a test, a spec, or the design text. Everything else gets fixed. Before each fix, take it one step further, as z-design's consequence step does; `./zn done` refuses a fixed answer without `consequences:`.
5. Commit each fix as you make it (pushed by `./zn commit --phase code-review`). **Harvest the round** as z-design step 5.3 does: one entry per finding of `review-NNN.md` in the raft's `harvest.md` (any lesson, design ones included; a new one is usually `when: build` or `both`), then `./zn lessons --uncovered R0010` and `./zn lessons --check`. Then commit the refute file, the ledger and the lessons the same way. Post a comment `Review NNN addressed`, pasting the refute file's lines.
6. **Then the human.** There is no second reviewer. After this one revision, anything you refuted, any high finding you could not close (not answered `fixed`), and any Judged criterion ruled fail, goes in the raft document under `## Open to the human`, one bullet each: `- F2: <the finding>. Answer: <your answer>. Decision: <what the human must decide>` (a failed Judged criterion uses its `JC<n>` id). The raft can be `done` when that list is empty or every bullet carries `Ruled (user, YYYY-MM-DD): <their decision>`. Do not guess a ruling. A medium or low finding you fixed, or deferred to a backlog issue (`- F<n>: deferred <id>: <why>`; `./zn done` accepts that only for a medium or low finding), does not go on the list. Quote every deferred line in the PR comment. Then continue to Phase 5.

## Phase 5: Done
1. Append each issue's final Verification log entry and fill in the raft's "Addressed during execution". Commit with `./zn commit --phase deliver`.
2. `git fetch origin main` and merge it into the branch now (renumber colliding IDs, rerun `z-nile/check.sh --affected`, commit with `./zn commit --phase deliver`), so the PR is up to date before `done` and nothing needs changing after it.
3. **Confirm the harvest**: first harvest anything `./zn lessons --uncovered R0010` still lists, as Phase 4 step 5 says. That includes the design reviews of a raft prepped before lessons existed, which are harvested here by you. Then `./zn lessons --uncovered R0010` and `./zn lessons --check` must pass. Commit with `./zn commit --phase deliver`.
4. `./zn done R0010`. It re-verifies everything, marks the PR ready, then moves the items to `done/` and pushes the done commit.
5. Post a PR comment `Ready to merge at <short sha>` (no final report yet).

## Phase 6: Merge and clean up
Under `./zn dispatch` (headless) the run ends at Phase 5's `Ready to merge` comment: the merge of the run's PR is a human's gate, and the dispatcher records the run's spend after it. Skip this phase.
1. Merge the PR yourself, without waiting for a human, once every condition under "Merging" in the zz-rules skill holds. A pull request that changes only tooling is gated by `z-nile/check.sh --affected` on the branch. A pull request that changes a game is gated by the local full gate, `z-nile/check.sh --full`, in a clone of the exact head whose parent directories are not a checkout of this repo, and by `lune run scripts/cicd` there. The PR is mergeable. Record the **gate wall time** and the `slowest:` specs of the merge's gate in the final report and its PR comment. If the merge's gate fails, post a `BLOCKED:` comment naming the failing specs and stop with the PR ready and unmerged; in the raft worktree at the PR head, for each failing spec that `lune run z-nile/affected -- --base $(git merge-base origin/main HEAD)` does not list (every spec counts as listed when it prints `ALL`), file a graph-miss chore (zz-test, Graph miss) and say so in the comment, unless the spec also fails on `origin/main` (then it is a red `main`: say that instead). If another condition can't be met, post a `BLOCKED:` comment and stop; the final report then says BLOCKED. A re-run after main moves is required only when the merged-in commits select a spec for this pull request; tracker-only commits require none (zz-rules, Merging).
2. After the merge and before the final report, `./zn spend R0010 --phase deliver --time <minutes from done to merged>`.
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
