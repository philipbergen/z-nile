# Review 003: R0080 (design mode)
Inputs: prep worktree (R0080.md, R0080/check.sh, c0140 and c0030 documents, check.sh files and every acceptance spec; design-review-001/002, design-refute-001/002); prototype `.worktree/proto-r0080` (uncommitted workflow, library, commands, tracker skill Merging text). I ran the specs and the mutants below against a scratch copy of the prototype in the session scratchpad. The prototype and the prep tree are unchanged, apart from this file.
Dropped from review-002: F1, F2 (resolved as answered; evidence below).

Checked and found sound, so no finding:
- **review-002 F1 is closed.** `workflow.spec` pins the exact key set of the workflow, of the beta job and of every step, with only lowercase `name` ignored, and the exact values of checkout, setup, deploy, the comment env and the runtime step. `pipeline.spec` pins the runtime step at index 5 with exact keys, run and env. Baseline: 17 passed. I re-ran the round-2 classes and new YAML-level variants:
  - A duplicate `if: always()` after the runtime step's `if` fails, because Lune keeps the last value. Put before it, Lune keeps the correct value, but GitHub rejects a duplicate key, so the workflow is invalid and nothing goes green.
  - A YAML merge key fails closed, as in round 2. Case variants such as `Continue-On-Error` add an unknown key, so they fail too.
  - Booleans in YAML 1.1 form, such as `cancel-in-progress: no`, decode as strings and fail the `toEqual`.
  - A null-valued key (`continue-on-error: ~`) disappears from the decoded table, so the spec passes, but null isn't `true` on GitHub either. The same goes for a trailing `---` document. Neither turns a red result green.
  - One way to fake green is left: a shell payload in the comment step's `run` that edits `$GITHUB_PATH` or `$GITHUB_ENV`. That is sabotage, not a plausible implementation slip. Anything that names `ROBLOX` is caught.
  - A sixth step, a new job key or a workflow-level key now needs a chore that edits the promoted spec. That is by design, and the testing skill's "file a chore" rule covers it.
- **review-002 F2 is closed, and the merge text can be executed.**
  - `gh pr ready --undo` exists, and converting a draft back to ready fires `ready_for_review`, which is in the workflow's types.
  - `gh run view --json` has a `jobs` field, and its help points to `databaseId` as the id for `gh run rerun --job`.
  - The job-level rerun API reruns the job and its dependents. `beta` has none, and `gate`'s result is reused.
  - A job that was superseded while waiting for the concurrency group never gets a runner, so it has no steps. A timeout ends `cancelled` with steps. So the step-less test separates the two cases the rule needs to separate.
  - Rerun ping-pong between agents ends once the running holder finishes. The 20-minute job timeout bounds that wait, well inside the 60-minute bound.
  - The needles are full phrases. Deleting any one rule removes its needle.
- **Empty runtime tier.** `runSuite([])` passes, but `scripts.spec` requires `structure.luau`, so the tier can't silently go empty.

### F1 [low] Inside this repo, a beta that is "unconfigured" still counts as green for merging
Where: prototype `.claude/skills/tracker/SKILL.md` Merging 3 ("Unconfigured publishing ends `SUCCESS` with a warning, which is fine"); c0140 Solution ("Not configured is a green skip")
Evidence: The beta job's `if` already excludes forks, so in this repo "unconfigured" can only mean the secret or a variable was deleted or renamed in the repo settings. One example is a rotation done as delete-then-add. In that case `deploy-beta` warns and exits 0, the comment and runtime steps are skipped, and `beta` is `SUCCESS`. The merge rule then merges with nothing published and no runtime test run, and the only sign is a warning annotation. An expired key is different: it returns 401 and is red.
Critique: This is low, not medium, because it needs a settings change by the user, and round 1 accepted the skip so that forks stay green. The tempting fix, making the skip red in CI, turns a fork's own internal PRs red.
Consequences: A check on the merge side keeps forks green but adds one lookup for the agent.
Recommendation: Optional, now or as a follow-up chore. Before merging, the agent requires the PR comment `Published to Pickman (Beta): version N (commit <head sha>)` for the head sha (`gh pr view <pr> --json comments`). Add it as a `pipeline.spec` needle.

### F2 [low] The comment step's `run` is still matched by substring
Where: `workflow.spec` "comments the published version…"
Evidence: `run: true # gh pr comment "$PR" --edit-last --create-if-none …` passes both specs (17 passed) and RC1. The version comment is then never posted.
Critique: Nothing is merged or published differently because of it, and F1's recommendation would make the comment load-bearing. If F1 is adopted, pin the comment's `run` exactly, the same way the runtime step's is pinned.
Consequences: none.
Recommendation: `t.expect(collapse(comment.run)).toBe(<exact text>)`, if F1 is taken up.

### F3 [low] The start of the 60-minute bound is unclear after the ready event is re-fired
Where: Merging 3, the `CANCELLED` bullet
Evidence: "60 minutes have passed since the PR became ready". After `gh pr ready --undo && gh pr ready`, the PR "became ready" again, so the clock may restart. Either reading still bounds the wait (re-firing is limited to the no-run case), so the rule still terminates.
Recommendation: Say "since the first ready event for this head sha".

Verdict: approve
