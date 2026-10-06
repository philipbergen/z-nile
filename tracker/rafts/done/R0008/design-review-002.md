# Review 002: R0008 (design mode)
Inputs: prep worktree at f1c10b5 (R0008.md, R0008/check.sh, c0015 and c0003 documents, check.sh files and acceptance specs, design-review-001.md, design-refute-001.md); prototype `.worktree/proto-r0080` (uncommitted, including the tracker skill edit and `.cache/mut80.py`). I spot-ran the workflow mutants below in a scratch copy, detached from git, against `workflow.spec` and `pipeline.spec`. The copy is in the session scratchpad and the prototype is unchanged.
Dropped from review-001: F3, F4, F5, F6 (resolved as answered). Parts of F1 and F2 are resolved (the `&&`/`||` and comment mutants are dead, and the probe ran); what remains is repeated below as F1 and F2.

Checked and found sound, so no finding:
- **Staging.** With the runtime step removed (c0015 complete, c0003 not started), `workflow.spec` passes 9/9. Its `count <= 2` and the runtime-step exemption let c0003 add its step without editing a sequestered c0015 spec. RC1 is raft-level, so it isn't run at c0015's completion.
- **YAML merge keys.** A `<<: *anchor` merge key makes Lune's YAML decoder raise an error ("Expected: MappingEnd"), so the spec fails closed. Plain anchors resolve to the values GitHub also sees.
- **`setup.sh` arguments.** It rejects unknown arguments before anything runs.
- **Timeout.** `timeout-minutes` doesn't count time spent waiting for the concurrency group, so a long queue isn't killed by the 20-minute bound.

### F1 [high] The parsed-YAML specs still pass a beta job that never deploys, ignores runtime failures, or deploys `main` (repeat of review-001 F1)
Where: `tracker/issues/c0015/acceptance/workflow.spec.luau` (step finders, the `has(step.run, "runtime-test")` exemption); `tracker/issues/c0003/acceptance/pipeline.spec.luau` (runtime step cases); R0008 `check.sh` RC1/RC2
Evidence: Each of these one-line changes to the prototype's `check.yml` passes both specs (15 passed, 0 failed). RC1 and RC2 are text greps, which none of the changes touch.
1. `continue-on-error: true` on the runtime step. A failing runtime test leaves the job `SUCCESS`, and the new merge rule then merges it.
2. `continue-on-error: true` on the beta job. Same effect, for every step.
3. `shell: "true {0}"` on the runtime step. The tests never run, and the step is green.
4. `if: github.event_name == 'push'` on the `deploy` step. Nothing is ever published. The comment and runtime guards skip, so the job is green.
5. `with: { ref: main }` on `actions/checkout@v4`. Beta gets `main`, and the runtime tests check `main`, not the PR.
6. `working-directory: tests/runtime` on the runtime step.

The parse fixed `&&`/`||` and comments, but the specs still assert only the keys they name. Any key they don't name is free, and several keys (`continue-on-error`, `shell`, a step `if`, `with`) change the result.
Critique: AC4/AC5 and the new merge rule rest on "beta is `SUCCESS` means published and tested". Mutants 1–4 break that while staying green. The tempting fix is to forbid these four keys one by one. That is the same substring arms race one level up: `strategy`, `container`, `defaults.run.shell` or `services` would be next.
Consequences: Pinning each step to an exact key set makes harmless additions such as `name:` fail, so allow `name` everywhere. The c0015 spec must still tolerate the runtime step, which arrives later, without becoming the hole: today any step whose `run` contains `runtime-test` is exempt from the "no `ROBLOX`" check, including a comment step with `# runtime-test` appended.
Recommendation: In `workflow.spec`, assert the shape exactly:
- The beta job's key set is exactly `{needs, if, runs-on, timeout-minutes, permissions, concurrency, steps}`. That rules out job `env`, `continue-on-error`, `defaults`, `container`, `strategy` and `services`.
- Every step's keys, apart from `name`, deep-equal the expected table:
  - checkout: `{uses = "actions/checkout@v4"}` with no `with`.
  - setup: `{run = "scripts/setup.sh --tools", env = {GH_TOKEN = "${{ github.token }}"}}`.
  - deploy: `{id, run, env}`, exact.
  - comment: keys are exactly `{if, run, env}`, `env` has exactly the four keys, and `run` is checked by substring as now.
- There are 4 steps, or 5 when the fifth's `run` equals exactly `lune run scripts/runtime-test -- "$VERSION"`. Exempt only that exact step, not any `run` that contains `runtime-test`.

In `pipeline.spec`, assert that the runtime step deep-equals `{if, run, env}` and that its `env` has exactly the four keys. Add mutants 1–6 and "comment step's run gains `# runtime-test` and the key" to both rules tables, as `run`.

### F2 [high] The new merge rule lets a PR merge with no beta result, and its cancellation handling can't be applied as written (repeat of review-001 F2(b))
Where: prototype `.claude/skills/tracker/SKILL.md` Merging, condition 3; c0003 Solution; `pipeline.spec` "merging requires the beta job…"
Evidence:
1. **A missing `beta` reads as acceptable.** The text says "*once* the run for this sha has a `beta` job it must be … `SUCCESS`". Its keep-waiting list names "a missing `gate`", not a missing `beta`. After `gate` turns `SUCCESS`, there is a window before `beta` is queued, and an agent that follows the text literally merges in it.
2. **The `ci-verify` fallback can't produce a beta.** The same paragraph says that if no `pull_request` run appears, the agent dispatches `scripts/ci-verify.sh`. That run is `workflow_dispatch`, which skips beta by design. The agent then either waits forever (`SKIPPED` means keep waiting) or merges on a run that has no runtime tests, because the dispatched run "has" a beta job.
3. **A superseded job can't be told apart from a timeout.** The rule says rerun on a supersede-cancel but treat a timeout as red. It doesn't say how to tell them apart, and c0015's own text says a timeout "ends the job as failed or cancelled". `statusCheckRollup` shows `CANCELLED` either way.
4. **The single rerun turns contention into `BLOCKED`.** Landing step 2 opens every capture and prep PR *ready*, so every one of them now runs beta too. With `cancel-in-progress: false`, only the newest waiting run survives, and a rerun is itself the newest. So agent A's rerun cancels B's waiting job, B's rerun cancels A's, and the "second cancellation is red" rule fires `BLOCKED` for a queue collision, not a defect.
5. **The text spec can't catch any of this.** Its needles (`` `beta` job ``, `` `SUCCESS` ``, `CANCELLED`, `gh run rerun`, `once`) are already met by text with gaps 1–4. `once` is met by "once the run for this sha…", so a skill that dropped the rerun rule entirely would still pass.

Critique: c0003 exists so that runtime tests really gate merges. Gaps 1 and 2 let a merge happen without them, gap 3 makes the rule non-executable, and gap 4 makes it stop for no reason. The tempting fix is "wait for beta to appear". Applied literally, that hangs on dispatched runs and on non-repo heads.
Consequences: Telling a superseded job from a timeout needs a concrete test. A job cancelled while waiting for the group never started, so `gh run view <run> --json jobs` shows it with no steps. A timeout has steps. Replacing the dispatch fallback with a real `pull_request` run means re-firing the ready event, which also reruns `gate`. That costs a few minutes and is harmless. An uncapped rerun needs a time bound instead.
Recommendation: Rewrite the beta part of condition 3:
- (a) For a PR ready from this repo, a missing `beta` check for the head sha means keep waiting, exactly like a missing `gate`.
- (b) A `workflow_dispatch` run never satisfies beta. If no `pull_request` run appears within about 5 minutes, re-fire it with `gh pr ready --undo <pr> && gh pr ready <pr>`, and use `ci-verify` only to diagnose `gate`.
- (c) For a `CANCELLED` beta, check `gh run view <run> --json jobs`. A beta job with no steps was superseded: rerun it with `gh run rerun <run> --job <id>`, as often as needed, until it finishes or 60 minutes have passed since the PR became ready, then `BLOCKED:`. A beta job whose steps ran is a timeout or a manual cancel, and that is red.
- (d) Strengthen the `pipeline.spec` case so its needles name these specific rules: the missing-`beta` wait, "`workflow_dispatch` … does not" (or similar), the no-steps test (`--json jobs`), and the 60-minute bound. Each needle should be a phrase that only the intended rule produces, not a word that already appears elsewhere.
- (e) Put a line in R0008 Risks: every ready PR, captures and preps included, now publishes to Beta, and an expired `ROBLOX_API_KEY` blocks *all* merges until the secret is renewed.

Verdict: changes
