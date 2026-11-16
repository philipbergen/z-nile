# Review 002: R0075 (code mode)
Inputs: HEAD 3417e4d600b9eb62780f6cc9be2ec4ec88774424 (branch R0075-scaffold-arcade-homes; it holds origin/main 604e2c7b251b0321a7caa8ba3fc9633fc7c79ea2); `git diff origin/main...HEAD` (135 files); the fix delta `git diff 56991168..HEAD` (accbd34f plus the merge of main); R0075.md and its check.sh; c0184.md, its check.sh and acceptance/; c0244.md, its check.sh and acceptance/homes.spec.luau; review-001.md, refute-001.md and harvest.md (read after the findings below were formed).
Dropped from review-001: none. F1 is fixed in the code (see the evidence), but its recommended end-to-end case with a fixture registry was not written (F2 below). F2, F3 and F4 are fixed.

Evidence run (in the worktree unless it says the scratch clone; the clone is `git clone --shared` of HEAD under $TMPDIR, outside the repository; every probe went through `./zn run --time`):
- `z-nile/check.sh --full`: **exit 1**. `== format (stylua --check) (2.3s, FAILED)`, "Diff in z-nile/.tracker/issues/active/c0244/acceptance/homes.spec.luau" (line 18, the `payload` line, and lines 60-63, the hook case's `it(...)`). The gate stops after its static stages, so no spec stage ran.
- `bash z-nile/.tracker/rafts/active/R0075/check.sh`: `FAIL RC0: project gate passes (full)` (the same stylua diff), PASS for the c0184 and c0244 checks and promote-check: 3/4, exit 1.
- `./zn check c0244`: AC1 PASS. `./zn check c0184`: AC1-AC9 PASS. `./zn promote-check R0075`: OK (5 specs copied).
- Spec suites, since the gate never reached them: `lune run tests/run` in each home: z-nile 1345/0, pickman 1811/0, arcade, portal, snake, invaders, asteroids 21/0 each.
- `stylua --check` on boundcmd.luau, guard-bash.luau, skills.luau, main.luau, home.luau, homespec.luau, cachepaths.luau: clean. Only the c0244 spec is unformatted.
- Sequestration: the listing gives `A z-nile/.tracker/issues/active/c0244/acceptance/homes.spec.luau` and `A z-nile/.tracker/issues/active/c0244/check.sh`. Both are the emergent issue's own new files, which is expected. Nothing else is listed, and `git diff --summary origin/main...HEAD | grep -i 'mode change'` finds nothing.
- The hook end to end (JSON piped into `lune run z-nile/guard-bash` with `ZN_CHECKOUT` set to the worktree). Exit codes, branch then origin/main's guard-bash and boundcmd copied to scratch:
  - `lune run snake/tests/run`: 0 (main: 2).
  - `nowhere/tests/run`: 2.
  - `Snake/tests/run`, `snake//tests/run`, `snake/tests/run/../../probe`: 2.
  - `./snake/tests/run.luau`: 0.
  - `cd snake && lune run tests/run`: 0.
  - `cd /tmp && lune run snake/tests/run`: 2. cwd `/tmp`: 2.
  - `/tmp/x/snake/tests/run`: 2.
  - cwd `pickman/` with `../snake/tests/run`: 0.
  - `<checkout>/nowhere/tests/run`: 0 (main: 0, F3).
  - `<checkout>/z-nile/.cache/probe/tests/run.luau`: 0 (F3).
  - cwd `pickman/` with `../../../../snake/tests/run`: 0 (main, with pickman: 0, F3).
  - cwd `z-nile/.cache` with `snake/tests/run`: 0 (main, with pickman: 0).
- Fail open: `projects.load` raises on a missing or unparsable registry ("no z-nile/projects.toml in …", `error(err, 0)`), and guard-bash catches it in a `pcall` and leaves `homes` nil. `projects.parse` only ever yields a home that is a plain name or `.`, so homeRunner's `.`/`/` filter can only meet `.`. The hook's cost is 17 ms per call against 16 ms on main (5 calls each).
- Mutants of c0244, run in the scratch clone with `lune run tests/run -- .tracker/issues/active/c0244/acceptance/homes.spec.luau` (baseline 7/0):
  - B, any `^[^/]+/tests/run$` once homes is set: killed (2 cases).
  - C, no `/` filter: killed.
  - G, `CTX.homes = c.homes or CTX.homes`: killed.
  - **A, guard-bash reads `projects.load(call.cwd)` instead of ZN_CHECKOUT: survives, 7/0.**
  - **D, guard-bash reads the registry but then passes the hand list `{arcade, portal, snake, invaders, asteroids}`: survives, 7/0.**
  - E, the `""`/`.`/`..` filters removed: survives (unreachable, see F2).
  
  Each surviving mutant's diff was printed to confirm it applied.
- Cases that kill A and D, run on the branch and on each mutant: a fixture checkout `$TMPDIR/fx/z-nile/projects.toml` naming `pickman` and `zz`:
  - Branch: `zz/tests/run` 0 and `snake/tests/run` 2. Mutant D: 2 and 0.
  - cwd `<checkout>/pickman` with `lune run ../snake/tests/run`: branch 0, mutant A 2.
- review-001 F4's fix: in the scratch clone, with `snake/skills/.DS_Store` present, `tests/acceptance/c0115/docs.spec.luau` gives 7/0.
- review-001 F2 and F3: the Verification log's Deviation 2 now names the real cause, and the `buildLessons` comment names the extended skills (read in `git show accbd34f`).
- Lessons: `./zn lessons --when build` was read against the delta. The hits are zz-execute/fix-rounds-rerun-every-member-check (F1), zz-test/pin-call-site-arguments (F2) and zz-test/fixtures-leave-nothing-a-guard-trusts (F2's fixture).

### F1 [high] The full gate is red: c0244's spec is not stylua-formatted, so RC0 fails and `./zn done R0075` cannot pass
Where: `z-nile/.tracker/issues/active/c0244/acceptance/homes.spec.luau:18` and `:60-63`. Raft check.sh, RC0.
Evidence: `z-nile/check.sh --full` gives `== format (stylua --check) (2.3s, FAILED)`, "Diff in z-nile/.tracker/issues/active/c0244/acceptance/homes.spec.luau", and exits 1. The raft's own check.sh gives `FAIL RC0: project gate passes (full)`, 3/4, exit 1. The fix commit accbd34f added the spec, and c0244's Verification log records only `lune run tests/run -- c0244 homes.spec, c0191 boundcmd.spec, tooling bounded-review.spec`. The gate and the raft's check were not rerun after the fix round. The c0184 log line "Raft check.sh (RC0) … 3/3 PASS" predates c0244.
Critique: the raft's exit criterion fails, and the PR cannot leave draft or be merged green. There are two tempting fixes. One is to rerun only `./zn check c0244`, which never runs the format stage. The other is to reformat by hand and change a token on the way.
Consequences: the only fix edits a file headed SEQUESTERED. It is the emergent issue's own new file (listed `A`, not `R100`), written in this branch and first reviewed in this round, so a formatting-only change keeps its content as reviewed here. If the lead holds that an emergent spec is frozen from its first commit, the only path is to escalate.
Recommendation: run `stylua` on that one file, and confirm that `git diff -w --word-diff` shows only line breaks. Then rerun `z-nile/check.sh --full` and `bash z-nile/.tracker/rafts/active/R0075/check.sh`, both green, and log both runs in c0244's Verification log. If F2's cases are added to the same file, format after adding them.
Lesson: zz-execute/fix-rounds-rerun-every-member-check

### F2 [medium] (repeat of review-001 F1's recommended end-to-end case) c0244's hook cases never give the hook a registry or a cwd that differs from the real checkout, so a hand list or a registry read from the wrong folder passes AC1
Where: `z-nile/.tracker/issues/active/c0244/acceptance/homes.spec.luau`, the cases "the hook reads the registry of its checkout…" and "a checkout whose registry cannot be read…". c0244.md, Rules and mutants, row "only the registry's homes count" ("reasoned").
Evidence: in the scratch clone the spec stays 7/0 under two mutants:
- **D**: guard-bash loads the registry and then passes `{ "arcade", "portal", "snake", "invaders", "asteroids" }`, the hand list review-001 F1 was about.
- **A**: guard-bash reads `projects.load(call.cwd)` instead of `ZN_CHECKOUT`.

Every hook case passes the same folder as `cwd` and `ZN_CHECKOUT`, and the one checkout with a registry is the real one, so it lists exactly today's homes. The case "only the registry's homes count" exercises only the pure `boundcmd.check` with a hand-built `Context`, not the reader that fills it. Review 001 F1 recommended "end to end through `guard-bash` with a fixture registry naming a third home". That case is not there. Mutant A is realistic: an agent's cwd is often a home such as `<worktree>/pickman`, where `projects.load` fails, `homes` becomes nil and `../snake/tests/run` is refused again. Separately, the case "a home name that is not a plain folder adds nothing" is half vacuous. `normalise` strips every leading `../` and `./`, so the home `../x` can never equal a target. Its first assertion passes without any filter, and mutant E (the `""`/`.`/`..` checks removed) survives. Only `a/b` tests the filter.
Critique: AC1 says the seatbelt "takes every registered home's runner from the registry", and the spec cannot tell that from a hand list. That is exactly the defect class this issue exists to remove. The tempting fix is a sentence in the Rules table. A case on the pure function does not reach the reader either.
Consequences: a fixture registry is a file guards may trust (zz-test/fixtures-leave-nothing-a-guard-trusts). It goes under `z-nile/.cache/<unique>`, is removed in a `pcall`-protected teardown, and a final assertion checks that it is gone. The hook's payload cwd must be a real folder inside the checkout for the relative rule to apply.
Recommendation: add two hook cases, in homes.spec if the lead treats the emergent spec as editable in this first review (one edit together with F1's reformat), otherwise in a new tooling spec beside `z-nile/tests/tooling/bounded-review.spec.luau`:
1. A fixture checkout `z-nile/.cache/c0244-fixture-registry/z-nile/projects.toml` naming `pickman` and a home the real registry lacks (`zz`). `lune run zz/tests/run` exits 0 and `lune run snake/tests/run` exits 2 (kills D; run: branch 0/2, D 2/0).
2. `ZN_CHECKOUT` = ROOT with payload cwd `ROOT/pickman` and `lune run ../snake/tests/run`: exit 0 (kills A; run: branch 0, A 2).

Change the Rules and mutants rows to `run: killed` with these mutants. Either drop the `../x` assertion or say in its comment that `normalise` already refuses it.
Lesson: zz-test/pin-call-site-arguments

### F3 [low] The absolute and `../` forms are not registry-driven: any `<checkout>/<x>/tests/run`, and `../`… paths that leave the checkout, pass the seatbelt
Where: `z-nile/engine/boundcmd.luau` `toolingMatch` (the absolute branch's suffix loop over `TOOLING`) and `normalise` (strips any number of leading `../`). c0244's case "an absolute runner path under the checkout counts for a registered home".
Evidence: both of these exit 0 on the branch, and the same forms exit 0 on origin/main:
- `lune run <checkout>/nowhere/tests/run`.
- `lune run <checkout>/z-nile/.cache/probe/tests/run.luau`, a scratch probe that would run unbounded.

From cwd `pickman/`, `lune run ../../../../snake/tests/run` (outside the checkout) exits 0, as `../../../../pickman/tests/run` already did on main. The c0244 absolute case passes whether or not `snake` is in `homes`, so it proves nothing about the registry, although its name says it does.
Critique: this was not introduced here. c0191's rules are older, and c0244's Non-goals exclude changing which commands are refused. But the rule this raft relies on, that only a registered home's jailed runner is tooling, holds only for the relative form. The source's own comment says "A scratch copy of the tooling is not the gate's". After review-001 F1 and this round, this is the second hole found in the same path-matching mechanism.
Consequences: making absolute targets resolve by checkout-relative key changes the refusals of a promoted c0191 spec's mechanism. It needs its own issue, with a check that no promoted c0191 case pins the suffix behaviour.
Recommendation: capture a z-nile issue (`./zn new issue d …`) so that `toolingMatch` resolves every target, absolute or `../`, to a path relative to the checkout (fail if it leaves the checkout) and then consults `TOOLING` and `homes` alike. List these forms as its spec cases. Do not change it in this raft.

### F4 [low] c0244's bookkeeping: not listed under the raft's "Addressed during execution", and its spend reads zero
Where: R0075.md "Addressed during execution" (still only the template comment). `z-nile/.tracker/rafts/active/R0075/spend.md` (`| c0244 | chore | yes | 0 | 0 | 0.0 | 0 |`). Commit accbd34f's trailer `Issue: c0184 +84/-6 30.0m code-review`.
Evidence: `git log origin/main..HEAD -- z-nile/.tracker/rafts/active/R0075/R0075.md` is empty. zz-rules, Emergent issues, step 4: "List it under the raft's 'Addressed during execution'". Its last line reads "Its spend counts toward its own type, which is how rework is measured". The commit that wrote c0244's code and spec credited all 84 lines and 30 minutes to c0184.
Critique: metrics will show the emergent issue as free, and the raft document doesn't say why the PR touches boundcmd and guard-bash.
Consequences: none beyond the records.
Recommendation: add `- c0244: R0075 review-001 F1, the seatbelt's hand list stopped at pickman; it could not wait because the Problem's "every hand-named pickman path" outcome is this raft's` under "Addressed during execution". Book the F1/F2 fix commits under `Issue: c0244` (or `./zn spend c0244 …`).

Candidate lesson (for the lead; a reviewer writes no lesson file):
- zz-execute: after a fix round adds a new spec or source file (an emergent issue's included), run the full gate, not only the new specs, because format and lint stages see the new file and `./zn check` does not. This may be a note on fix-rounds-rerun-every-member-check rather than a new lesson. Check: did `z-nile/check.sh --full` and the raft's check.sh pass after the last fix commit?

Verdict: changes
