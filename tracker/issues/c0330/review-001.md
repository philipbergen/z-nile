# Review 001: c0330 (code mode)
Inputs: main...HEAD at 78fde99 plus working tree; .claude/skills/{execute-raft,review,tracker}/SKILL.md, tracker/issues/c0330/{doc,check.sh}, scripts/tracker/main.luau, scripts/tracker/spend.luau, scripts/lib/ac.sh. Note: no raft dir exists, so this file lives in the issue directory. `tracker.sh done` would not read it here.

### F1 [medium] check.sh AC1 and AC3 pass on a doc that does not do what the AC says
Where: tracker/issues/c0330/check.sh ac1, ac3
Evidence: ac1 requires the string `Review NNN started` and any case-insensitive `push` anywhere in Phase 4. The Phase 4 intro line already contains "Push at every step", so the push half is always true. Delete the "make sure the tree is clean and git push is done" clause from step 1 and AC1 still passes, as it does if the started comment is posted after the reviewer is launched. ac3 only greps `Review NNN addressed`, so it passes with no push, no refute-file commit and no `gh pr comment` (AC3 says "pushed and commented"). ac2 similarly matches strings anywhere in the Phase 4 range, not in the step that owns them. The sed range `/^## Phase 4/,/^## Phase 5/` also runs to EOF if the Phase 5 heading is renamed, which makes the greps more lenient. Nothing checks the cadence outside Phase 4 (issue-finished and experiment comments, the BLOCKED comment, the tracker skill's list of events).
Fix: since check.sh is sequestered, tighten it before execution. Grep for `git push` within step 1, or for a line matching `Review NNN started.*` together with `gh pr comment`. Require `Review NNN addressed` on the same line as `refute`. Also add a check for "issue" plus "tracker.sh check" plus "comment" and for `BLOCKED` in the tracker skill.

### F2 [medium] The "throughout phases 1-2" comment rule is in the wrong place, and Phase 3 has no cadence
Where: .claude/skills/execute-raft/SKILL.md:77 (last paragraph after Phase 5)
Evidence: The sentence "Throughout phases 1-2, also post a short PR comment when an experiment round finishes and when each issue passes `tracker.sh check`" sits at the end of Phase 5, after the final-report step. An agent following phases in order reads Phases 1-2 without seeing it. Phase 2 step 4 ("Finish the issue") is where the issue-finish comment belongs, and Phase 1's commit step is where the experiment comment belongs. The c0330 Solution says "Phase 0-3", and the tracker skill lists "an issue finishes", but no AC covers it. The wording is also unclear as to whether the comment is required or optional ("also post a short").
Fix: move the two comments into Phase 1 (after the experiments commit) and Phase 2 step 4, and delete the trailing paragraph. Use imperative wording.

### F3 [medium] Re-review file format conflicts with tracker.sh done's parser
Where: .claude/skills/review/SKILL.md "Visible record"; scripts/tracker/main.luau reviewProblem (lines ~408-440)
Evidence: The new text requires a re-review to "make clear which earlier findings were dropped or repeated". reviewProblem treats every `\n###\s+(F%d+)` heading in the latest review as a finding that needs a `- F<n>: fixed|refuted` line in refute-NNN.md. If the reviewer lists dropped findings as `### F2 [dropped] ...` headings (the natural reading, since the format uses F headings), `done` fails with "findings not answered" for a finding the reviewer withdrew. Finding ids also restart at F1 each round, so "repeated F3" is ambiguous against the new round's F3.
Fix: tell the reviewer to record dropped findings in a non-heading line under the Inputs line, for example `Dropped from review-001: F2, F4`, and to give repeated findings new ids with `(repeat of review-001 F3)` in the claim.

### F4 [medium] The approve-with-no-findings path is undefined
Where: execute-raft Phase 4 steps 4-5
Evidence: Zero findings with `Verdict: approve` is valid (review skill), and `done` accepts it without a refute file. Step 5 then says to post "Review NNN addressed, pasting the refute file's lines". There is no refute file and nothing to paste, so the agent either invents an empty refute file or skips the step. The comment in step 3 already carries the verdict, so the "addressed" comment is redundant in this case. AC3 would pass regardless.
Fix: add "If the verdict is approve with no findings, skip steps 4-5 (no refute file, no addressed comment)." Also say what to post when only low findings remain with approve.

### F5 [medium] Who commits the review file is ambiguous, so it can be committed twice or by the wrong party
Where: execute-raft Phase 4 step 3; review/SKILL.md "Visible record"
Evidence: Step 3 tells the author to run `tracker.sh commit -m "R0010: review-NNN"` "as soon as it's written". The review skill says the "author's harness" commits it and never says the reviewer must not commit or push. A reviewer subagent with Bash can run `git commit` or `git push` itself (a plain `git commit` is banned for tracked work). Because a Claude Code subagent shares the working tree, the author cannot know "as soon as it's written" until the subagent returns. Also `tracker.sh commit` runs `git add -A`, so anything the reviewer left in the tree (for example output from `check.sh --full`, or stray edits) is swept into the review commit and attributed as spend.
Fix: in the review skill add "Do not commit, push or comment; only write the file." In execute-raft step 3, say to run the commit after the reviewer returns and to verify `git status` shows only `review-NNN.md` first.

### F6 [low] Reviewer runtime is attributed to an issue as author time
Where: execute-raft Phase 4 step 3; scripts/tracker/spend.luau elapsedMinutes
Evidence: `tracker.sh commit` without `--time` uses the minutes since the last commit (capped at 45), attributed to the focused issue or the raft. The review commit lands after the reviewer's whole run, so review wall time is booked to the focused issue and inflates spend (the metrics skill's rework figure is based on spend records).
Fix: recommend `--time 0` on the review-file commit, or say the review round's time is attributed to the raft deliberately.

### F7 [low] Failure handling for push and gh is unspecified
Where: execute-raft Phase 4 intro; scripts/tracker/main.luau push()
Evidence: `push()` silently does nothing when there is no upstream and only prints a notice when there is no origin. `gh pr comment` fails if `gh` is unauthenticated or the branch has no PR. The skill says "Never hold review state locally" but does not say what to do when a comment fails. The reviewer would then be launched against a state the PR does not show, or the agent might block for no good reason. Step 1 says "`git push` is done" but tracker.sh commit already pushes, and a bare `git push` differs from the tracked path if the branch has no upstream.
Fix: add "If push or `gh pr comment` fails, retry once; if it still fails, note it in the verification log and continue (do not skip the review), and mention it in the final report." Use `git push -u origin HEAD`-safe wording or check with `git status -sb` that the branch is not ahead.

### F8 [low] Design mode and doc completeness
Where: review/SKILL.md "Visible record"; c0330 issue doc
Evidence: Design-mode reviews are explicitly out of scope (non-goal), and the review skill's new section only speaks of code mode, but does not say design mode is exempt, so a design reviewer may look for a PR to comment on. Also the issue doc still has empty Design, Touched-module reasons, Test plan, Implementation steps and Verification log sections, and `design: draft`. The escalation path (BLOCKED) is covered by the tracker skill line, but execute-raft's Stop-conditions section was not touched and does not say to also push the review files.
Fix: add one line "Design mode has no PR yet; nothing here applies." Fill or mark the empty sections n/a, and set `design` appropriately.

## Verified
- `tracker.sh commit` does push (recordAndCommit calls push(), guarded by hasUpstream), and works with review files since `git add -A` includes them and spend rows are skipped for zero-line commits. The claim "(this pushes)" is correct when an upstream exists (`start` sets `-u`).
- tracker skill line 43 matches this; no contradiction with the `done` row.
- AC4's two greps do match the added headings.

## Judged criteria (code mode only)
None defined for c0330.

Verdict: changes
