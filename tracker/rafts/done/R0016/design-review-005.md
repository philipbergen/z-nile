# Review 005: R0016 (design mode)
Inputs: head ca60ba2 ("Merge origin/main into R0016; re-prep c0048 on setup.sh --tools"). Re-prep of c0048 only: c0048.md, c0048/check.sh, c0048/acceptance/{board-workflow,board-docs}.spec.luau, `.github/workflows/board.yml` as implemented, R0016.md and R0016/check.sh; review-001 (F1 is the trigger for this round); `scripts/setup.sh`, `check.yml`, `tests/acceptance/c0015/{tools,workflow}.spec.luau`, `tests/acceptance/c0001/ci-workflow.spec.luau`.
Runs: `bash tracker/rafts/active/R0016/check.sh` gives 8/8 PASS (full gate, all three member check.sh, promote-check, RC1-RC3), tree clean afterwards, so the main merge didn't break c0047 or c0050. `AC_LIST=1` on c0048/check.sh lists AC1-AC7 in the order and with the numbers of c0048.md. `git diff origin/main HEAD -- scripts/setup.sh SETUP.md .github/workflows/check.yml` is empty. On GitHub, run 36823675498 (pull_request): `beta` step "Run scripts/setup.sh --tools" succeeded with the same `run` and `GH_TOKEN` env that board.yml uses. That is direct evidence for the setup half of E3. Mutants, all on a scratch copy (`git archive HEAD`): the table's re-prep rows (setup without `--tools`, an extra env var, no `GH_TOKEN`, build without `--out`), plus job `if` removed and a `run_id` group. Each fails `board-workflow.spec` (7 passed, 1 failed), so the `run` marks hold. New mutants are in F1 and F4.

### F1 [medium] board-workflow.spec doesn't pin the step list, so a job that runs the full gate, or uploads a file other than the built board, passes AC1 and AC2
Where: `tracker/issues/active/c0048/acceptance/board-workflow.spec.luau` (cases "bootstraps with setup.sh --tools…", "builds the board after setup…", "checks the repository out…"). The Design says "exactly", and the Rules row says "setup is the tools-only mode … and nothing else".
Evidence: each mutant below was applied to `board.yml` on the scratch copy and gives `8 passed, 0 failed`:
- (a) adding a step `- run: scripts/check.sh --full` before the build. The job then runs the whole gate on every push to `main`, which `--tools` exists to avoid (Scalability: "no tests, no gate").
- (b) adding a step `- run: echo stale > dist/board.html` between the build and the upload. The artifact is then not the built board.
- (c) changing the build to `run: scripts/tracker.sh board --out dist/board.html || true`. The `%S+` capture still reads `dist/board.html`, and a build that fails after writing part of the file uploads green.
- (d) giving the checkout `with: ref: dev`. That builds another branch's tracker as "the" board.
- (e) removing `retention-days: 30`. Retrieval and the Design both state 30 days.

AC5 and RC2 run their own command, so neither catches (b) or (c).
Critique: the spec locates steps by substring and checks their relative order. It never says that these are the only steps, or that each step is exactly as designed. The tempting fix is one more `find`-style check per mutant. That leaves the next inserted step uncaught.
Consequences: pinning the whole step list turns the spec into a near-literal copy of the Design block. Any later legitimate edit, such as a `timeout-minutes` or a cache step, then needs a chore. That fits "exactly" and CI work is always a chore anyway, but say it in the Design so it reads as intended. The Rules table needs a row for each new pin, and those rows need mutant runs.
Recommendation: in "checks the repository out before anything else" (or a new case, "has exactly these four steps"), assert `#steps == 4`. Then assert:
- `steps[1]` has `uses == "actions/checkout@v4"` and `with == nil`;
- `steps[2].run` is `scripts/setup.sh --tools`;
- `steps[3].run == "scripts/tracker.sh board --out dist/board.html"` exactly, with `env == nil`;
- `steps[4].uses == "actions/upload-artifact@v4"`, and `keys(steps[4].with)` equals `{ "if-no-files-found", "name", "path", "retention-days" }`, with `retention-days == 30`.

Add the Rules rows "only the four designed steps" (mutants a and b), "the build command is exact" (c), "checkout of the pushed ref" (d) and "30-day retention" (e). Mark them `run` after the mutants fail, and record the runs in E4.

### F2 [medium] The sequestration check has no usable baseline after the re-prep, so the executor can't run it and later edits to c0048's specs wouldn't show
Where: R0016.md "Addressed during execution" ("differ from the start commit on purpose"); execute-raft Phase 4 step 3; the review skill's code mode item 2 (`git diff <tracker: start commit> -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` "must be empty").
Evidence: `git diff --stat c603241 HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` lists 23 files. Only three are R0016's intended changes: `board-workflow.spec`, the deleted `setup-skip-gate.spec`, `c0048/check.sh`, and `R0016/check.sh`. The rest come from the main merge: c0003/c0015/R0008 moved to `done/`, and new c0051/c0052/c0053 check.sh files. The protocol's "must be empty" check now fails by construction. The Addressed note says the difference is on purpose, but it gives no baseline the rest of execution can be checked against. An edit to `board-workflow.spec` made after this review (for example, to quietly fix F1 during execution) would look like part of the sanctioned re-prep.
Critique: an executor told "must be empty" either stops and escalates again or learns to ignore the check, and so would the review-002 reviewer. The tempting fix is "the reviewer should eyeball it", which is no check at all.
Consequences: the new baseline has to be the commit that lands this round's answer (design-refute-005, including any spec change F1 brings), not ca60ba2. Otherwise F1's own spec edit breaks it. The diff also has to be scoped to the members, because any later `main` merge moves other items' sequestered files again.
Recommendation: in "Addressed during execution", name the new baseline as the commit that records design-refute-005, and give the exact replacement command: `git diff <that sha> -- 'tracker/issues/active/c04[568]0/check.sh' 'tracker/issues/active/c04[568]0/acceptance/**' tracker/rafts/active/R0016/check.sh`. That command must be empty from then on. List the start-commit diff that is expected for R0016's own files: the three c0048 files plus RC1. The code reviewer then checks both.

### F3 [low] R0016.md still describes the old `setup.sh` change in two places
Where: `tracker/rafts/active/R0016/R0016.md:31` ("`scripts/setup.sh` changes under c0048 force a full run of the gate, which both issues need anyway") and `:44` (Rollback: "revert the squash commit (one file plus a small `setup.sh` guard)").
Evidence: c0048.md now says "no change to `setup.sh` or `SETUP.md` remains in this issue", and `git diff origin/main HEAD -- scripts/setup.sh` is empty. No other R0016/c04xx live document mentions `PICKMAN_SKIP_GATE` except as history (c0048.md Solution note, E5, the Verification log). stream-review-c0048-001 is a historical record and stays as it is.
Critique: an executor or the code reviewer reading Order & dependencies would look for a `setup.sh` change that should not exist.
Consequences: none.
Recommendation: line 31: "the full gate runs anyway (`scripts/tracker/main.luau` under c0050 forces `ALL`)". Line 44: "revert the squash commit (`board.yml`, skill text, `tracker/main.luau`)". Also correct "both issues" to all three.

### F4 [low] Nothing behavioural guards check.yml's gate any more. main's c0015 tools.spec is text-only, and a CI-conditional skip passes everything (pre-existing on main, not introduced by this raft)
Where: `tests/acceptance/c0015/tools.spec.luau` (rerun by c0048 AC3); `scripts/setup.sh:67`; the dropped `setup-skip-gate.spec`. design-review-003 called that spec "the CI gate's only guard" against a skipped stage.
Evidence: on the scratch copy, `if [[ ${1:-} == --tools ]] || [[ -n ${CI:-} ]]; then` passes c0015/tools.spec, c0015/workflow.spec and c0001/ci-workflow.spec (21 passed, 0 failed). With that edit, check.yml's `gate` job prints "tools only: gate skipped" and goes green without running a spec. tools.spec only checks that the text `== --tools ]]` comes before `exit 0`, which comes before `say "gate"`.
Critique: what board.yml relies on is that `--tools` installs the tools and exits 0 before the gate. tools.spec covers that well enough, and a regression there costs minutes, not correctness, so AC3 is honest. The gap is the reverse direction, the gate being skipped when it shouldn't be. It existed on `main` before R0016, and since c0048 no longer touches `setup.sh`, the dropped spec isn't a regression of this raft. Widening c0048 to fix main's guard would be new work.
Consequences: a behavioural guard needs to run `setup.sh`'s tail against a stub gate, as the old spec did, under `CI=1` with no argument (the gate runs) and with `--tools` (it doesn't). That is a new chore with its own `Overrides:` analysis against c0015/tools.spec.
Recommendation: don't change c0048. Per "ask before new work", put a proposed backlog chore ("behavioural guard that setup.sh runs the gate unless `--tools`") in the final report and let the human decide.

Notes, no finding:
- Board workflow on GitHub: the setup step is byte-identical to `check.yml`'s `beta` step, which has succeeded on GitHub. `tracker.sh` prepends `~/.rokit/bin` itself and `setup.sh` also writes `GITHUB_PATH`, so the build step finds `lune`. `contents: read` is enough for `gh api rate_limit` and for the artifact upload. There is no `timeout-minutes`, but the job holds no lock and a newer push cancels it, so it is acceptable.
- AC numbering: c0048.md AC1-AC7 match check.sh's labels and order, and R0016.md RC0-RC3 match the raft check.sh. RC1's `grep -F` would also match a commented line, but AC2 pins the step exactly, so RC1 is only a pointer.
- Gate protection: c0001/ci-workflow.spec pins the gate job to exactly `run: scripts/setup.sh`, and c0015/workflow.spec pins `beta` to `--tools`. Only those two workflows plus board.yml exist, so review-001's suggested "nobody else passes `--tools`" pin isn't needed.
- promote-check passes, and `tests/acceptance/c0048/` doesn't exist yet.

Verdict: changes
