# Review 001: R0080 (design mode)
Inputs: prep worktree at 6515fa5 (R0080.md, R0080/check.sh, c0140 and c0030 documents, check.sh files and all 13 acceptance specs); prototype at `.worktree/proto-r0080` (uncommitted files listed in the brief). I ran all 13 specs against a scratch copy of the prototype (65 cases pass) and spot-ran the workflow mutants below in that copy. The copy has been deleted.

Checked and found sound, so no finding: `pull_request` (not `_target`) plus the same-repo guard; the implied `success()` on `needs: gate` (a skipped or failed gate skips beta, so drafts, pushes and dispatches never publish); no `${{ }}` reaches a `run:` line; the loopback-only seam (the anchored patterns refuse `@`, suffix and path tricks); a transport error prints the Lune error and stack but not the key (tried against a closed loopback port); `net.serve` binds 127.0.0.1 only and the random port is seeded per process; promoted specs need only Rojo and a loopback port (the gate has both), write only under the git-ignored `.cache/`, and override every `ROBLOX_*` variable they depend on; version 5 on Beta (main at 2973d6c) already has `Server.Main`, the three remotes and `CharacterAutoLoads = false`.

### F1 [high] `workflow.spec` and `pipeline.spec` pass workflows that publish drafts, forks and pushes, or that cancel a publish in flight
Where: `tracker/issues/c0140/acceptance/workflow.spec.luau` (all cases), `tracker/issues/c0030/acceptance/pipeline.spec.luau` (guard cases), R0080 `check.sh` RC1/RC2
Evidence: The specs check for substrings in the workflow text. I ran two mutants of the prototype's `check.yml` in a scratch copy, and both passed `workflow.spec` and `pipeline.spec` (13/13):
1. The two `&&` in the beta job's `if:` changed to `||`. In expressions, `null == false` is true, so this publishes on fork PRs and drafts, and on a push to main.
2. `needs: gate` and the whole `if:` turned into YAML comments that still contain the asserted text, and `cancel-in-progress: true # was cancel-in-progress: false`.

The "nearest `if:` within 120/250 characters" guards are heuristics of the same kind. The rules table marks these rows `run`/killed, but only for the deletion mutants.
Critique: AC4 and AC5 are exactly the safety properties of this raft: who publishes, when, and with the key. A text match can't tell a condition from a comment, or `&&` from `||`. The tempting fix is more substrings (for example, asserting the absence of `||`). That makes the spec reject harmless layout and still misses other wrong forms (`!`, a guard on the wrong step, a step-level `if:`).
Consequences: Parsing the YAML pins the structure. It also makes exact-value asserts brittle against harmless reformatting of the `if:` text (folded scalar, spacing). So compare the condition after collapsing whitespace, not the raw text. Lune's YAML decoder reads `on` as the string key `"on"` (verified), so the trigger table can be asserted directly.
Recommendation: Rewrite both specs over `serde.decode("yaml", ...)`. I verified it works in Lune 0.10.5 on the prototype's file. Assert:
- `jobs.beta.needs == "gate"`.
- `jobs.beta["if"]`, with whitespace collapsed, equals the exact three-clause `&&` string.
- `concurrency` deep-equals `{group="beta-deploy", ["cancel-in-progress"]=false}`.
- Workflow `permissions` deep-equals `{contents="read"}` and beta's equals `{contents="read", ["pull-requests"]="write"}`.
- Beta's `env` has exactly the three keys with their exact expressions.
- The steps are in order: checkout, `run == "scripts/setup.sh --tools"`, `id == "deploy"` with `lune run scripts/deploy-beta`, then the comment step and the runtime step. Each of the last two has `if == "steps.deploy.outputs.version != ''"` and `env.VERSION == "${{ steps.deploy.outputs.version }}"`.
- No `run` string in any job contains `${{`.
- `on` and `jobs.gate.if` equal their current values.
- Every other job has no `secrets.` anywhere in its re-encoded table.

Keep the `secrets.ROBLOX_API_KEY` count and the `echo`/`set -x` text rules, which are text properties. Add the two mutants above, plus "runtime step's `if` removed" and "guard on the comment step only", to both rules tables. RC1/RC2 in R0080 `check.sh` can stay as they are, because they back up the specs.

### F2 [high] Every check in the real environment happens after `tracker.sh done`, and the merge procedure ignores the `beta` job, so a broken deploy or a red runtime test merges
Where: R0080 *Experiments phase* ("Left for the executor's Phase 1 … verified by the raft's own PR becoming ready"); c0140 E4 and the comment fallback; c0030 E3 and OC1; `.claude/skills/tracker/SKILL.md` Merging, condition 3 (only `gate` must be `SUCCESS`)
Evidence:
- The raft PR becomes ready only inside `tracker.sh done` (tracker skill, Merging 3). Phase 1 runs before any code exists, and `workflow_dispatch` is excluded from beta by design. So the executor can't do E4 (`setup.sh --tools` on a fresh runner), E3 (`(getfenv() :: any).game` in Luau Execution), or the `gh pr comment --edit-last --create-if-none` check with an Actions installation token in Phase 1. (`setup.sh` itself notes that such tokens fail `/user`; E3 of c0140 only checked that the flags exist locally.)
- After `done`, the merging agent waits for `gate` alone and merges. Observed criteria "do not block the merge", and "a finished PR gets no unreviewed code changes". So if beta goes red, nobody applies the fallbacks, and the raft lands with a deploy that has never worked.
- The same holds for every later raft: c0030 exists to turn adapter criteria into Checked ones. But a red runtime test never blocks a merge, because merging looks only at `gate`.

Critique: The design says these unknowns are fail-fast experiments with fallbacks, but the lifecycle puts them after the point where a fallback can still be applied. The tempting fix is to "watch beta after merge". That leaves main broken until someone notices, and it still doesn't make runtime tests count.
Consequences: Making `beta` a merge condition adds new states:
- `CANCELLED`, when a newer ready PR superseded the pending job (last one wins).
- A long wait while another PR's publish holds the group.
- `SUCCESS` with only a warning when unconfigured (forks never merge here, so that is fine).

A Phase 1 probe needs the user's permission, as prep's did. It doesn't need a publish: Beta version 5 already contains everything `structure.luau` asserts.
Recommendation (needs a user decision, both parts):
- (a) Phase 1 probe. With the user's OK, add a one-off workflow on a throwaway branch, as prep did. It runs `scripts/setup.sh --tools` and then `lune run scripts/runtime-test -- 5` against the existing version 5. There is no publish, so Beta is unchanged. It also runs `gh pr comment --edit-last --create-if-none` on a scratch PR, twice, to prove the second run edits rather than adds. Record the pass or fail of E4 and E3 and the comment check in the issues before writing the job, so a fallback is applied in Phase 1.
- (b) Merge condition. Extend Merging condition 3 so that when the head sha's run contains a `beta` job, it must be `COMPLETED`/`SUCCESS`. On `CANCELLED` (superseded), rerun that job once with `gh run rerun <run> --job <id>` and wait; anything else is red. Add `.claude/skills/tracker` to c0030's Touched modules, with a text case in `pipeline.spec` that checks the skill names `beta` in the merge condition. Change "Left for the executor's Phase 1" in R0080 to say what (a) and (b) actually do.

### F3 [medium] The beta job has no `timeout-minutes` while it holds a repository-wide lock, and HTTP calls have no timeout
Where: c0140 Design, `.github/workflows/check.yml` beta job; `scripts/lib/opencloud.luau` `defaultRequest`
Evidence: `net.request` is called without a timeout, and Lune 0.10's request has none by default. A stalled connection to `apis.roblox.com` during publish or a poll keeps the job running until GitHub's 360-minute default. All that time it holds `group: beta-deploy`. Every other ready PR's beta job waits, and each newer one cancels the previous waiting one. The 5 × 60 s retry bound and the 120 s execute timeout in the design don't cover this.
Critique: This turns one network stall into a six-hour block on all Beta deploys and runtime tests, and with F2(b), on every merge. The tempting fix is a client timeout in Lune. Lune's `net.request` gives no portable way to set one.
Consequences: A job timeout ends as `CANCELLED`/failed, and the F2(b) merge rule must treat it as red, not as superseded. The bound must grow as runtime scripts are added: about 2.2 minutes per script worst case.
Recommendation: Set `timeout-minutes: 20` on the beta job. That is 5 minutes for publish retries plus room for about six runtime scripts at their 120 s cap. Document in c0030's Scalability section that the bound grows with the script count. Assert `jobs.beta["timeout-minutes"]` is a number ≤ 30 in the YAML-parsed `workflow.spec` (F1). Add a rules-table row whose mutant is "timeout removed".

### F4 [low] The key is in the job-level env, so `setup.sh --tools` and its downloaded tools run with it
Where: c0140 *Secrets*; `workflow.spec` "names the secrets only…" (`count == 1`); R0080 RC2
Evidence: Job-level `env` exposes `ROBLOX_API_KEY` to every step. That includes `rokit install --no-trust-check` (version-pinned, not hash-pinned downloads) and `selene`, `stylua` and `luau-lsp --version`, none of which need it. The spec's `count(text, "secrets.ROBLOX_API_KEY") == 1` rules out step-scoping.
Critique: The key must reach `lune` (and thereby `rojo`), but not the other tools. With step-scoping, the key is named twice, so the count rule changes.
Consequences: RC2 and the spec move from "named once" to "named only in the env of the deploy and runtime-test steps". The comment step and setup no longer see the key.
Recommendation: Put the three Roblox settings in the `env` of the `deploy` step and the runtime-test step only. In the YAML spec (F1), assert that those two steps' `env.ROBLOX_API_KEY` is `${{ secrets.ROBLOX_API_KEY }}` and that no other step or job, and the job `env`, names `secrets.`. Change RC2 to count 2 and require both occurrences inside the beta job.

### F5 [low] `tools.spec` locates `--tools` by its first appearance in the text
Where: `tracker/issues/c0140/acceptance/tools.spec.luau`
Evidence: `at("--tools")` returns the first occurrence. A correct implementation that documents the flag in the header comment (`# Usage: scripts/setup.sh [--tools]`) fails "installs the tools before it can stop", because the comment comes before `rokit install`. An unknown flag (`--tool`) silently runs the whole gate.
Critique: The spec penalises documenting the flag. The tempting fix is to forbid comments.
Consequences: none beyond the spec text.
Recommendation: Anchor on the condition, `string.find(text, "== --tools ]]", 1, true)`, instead of the bare flag. Optionally, make `setup.sh` reject unknown arguments, with a case asserting that the text contains the rejection.

### F6 [low] "Last one wins" means the last to finish the gate, not the newest push
Where: R0080 Theme and Risks; c0140 *Triggers and safety*
Evidence: The `gate` job has no concurrency, so push 1 and push 2 of the same PR both run it. If push 1's gate finishes later, its beta publishes after push 2's. Beta and the edited comment then show the older commit.
Critique: This is rare and harmless, but the docs promise newest-wins. A per-PR workflow-level `cancel-in-progress: true` group would fix the order, but it could also cancel a publish in flight.
Consequences: none if it's documented.
Recommendation: State in R0080 Risks and in SETUP.md that the order is gate completion. The comment already names the SHA, so readers can tell which commit Beta is running.

Verdict: changes
