# Review 001: R0001 (design mode)
Inputs: commit 560f766 (main, clean). Files: R0001-foundation.md, R0001/check.sh, c0001 and c0002 docs, check.sh files and acceptance/*.spec.luau, scripts/, tests/, .github/workflows/check.yml, .luaurc, default.project.json, SETUP.md. Experiments were run under .cache/rv/: the RC1 command on main, a detached-HEAD CI-style checkout of the lifecycle spec, @lune/roblox identity and deserialize, serde YAML decoding, and a copy of the repo with the acceptance specs promoted to tests/acceptance/ (plus a stub tests/lib/place.luau and an `@scripts` alias).

### F1 [high] RC1 passes today, with no tests/place directory at all
Where: tracker/rafts/R0001/check.sh:12-13; tests/run.luau:33-35
Evidence: when `tests/place` is missing or empty, `find` prints nothing and the command becomes `lune run tests/run --`. tests/run.luau treats "no files" as "collect all of tests/", so it runs the whole suite. On main right now the RC1 command prints `find: tests/place: No such file or directory` and `20 passed, 0 failed, 4 spec files`, then exits 0. RC1 is therefore satisfied without the place tier. The raft doc describes RC1 as `lune run tests/run -- tests/place`, but tests/run.luau cannot take a directory argument: `require("../tests/place")` fails.
Fix: `files=$(find tests/place -name "*.spec.luau" 2>/dev/null | sort); [[ -n $files ]] && out=$(lune run tests/run -- $files) && ...`. Also correct the command quoted in the raft doc.

### F2 [high] c0002 AC3 fails for the wrong reason: the `@scripts` alias does not exist and no document says to add it
Where: tracker/issues/c0002/acceptance/affected-place.spec.luau:4; .luaurc; c0002 Design, Touched modules and Implementation steps
Evidence: `tracker.sh check c0002` gives AC3 `error requiring module "@scripts/lib/graph": @scripts is not a valid alias`. .luaurc defines only logic, shared, tests and lune. Existing tooling specs use `../../scripts/lib/graph`, but the testing skill forbids relative requires in acceptance specs. The executor may not edit the spec, and no document authorises a .luaurc change, so by the execute-raft rules the executor must stop.
Fix: add to c0002's design and Implementation step 4: add `"scripts": "./scripts"` to .luaurc, list `.luaurc` under Touched modules, and add `@scripts` to the alias list in the testing and architecture skills.

### F3 [high] Promoting the acceptance specs turns the gate red after `done`
Where: tracker/issues/c0001/acceptance/tracker-lifecycle.spec.luau:91; tracker/issues/c0002/acceptance/resolve-require.spec.luau:63; the flow of `tracker.sh done`
Evidence: I copied the repo, moved both acceptance folders to tests/acceptance/<id>, and added a stub place.luau and the `@scripts` alias. Two failures appeared:
(a) `luau-lsp analyze ... tests scripts` reports `tracker-lifecycle.spec.luau(91,12): TypeError: Argument count mismatch. Function 't.expect' expects 0 to 1 argument, but 2 are specified`. The cause is that `string.find` returns multiple values.
(b) `tests/meta/architecture.spec.luau` fails "every require resolves" with `tests/acceptance/c0002/resolve-require.spec.luau: require("./A")` and `require("@self/B")`. The cause is that graph.luau's regex matches the require text inside the string literal on line 63.
`done` runs the raft check.sh *before* it promotes the specs, and nothing type-checks or meta-checks the specs in their promoted location. The raft goes "done", the PR is marked ready, and CI plus every later `check.sh --full` go red. Promoted specs cannot be edited, so each failure becomes a defect.
Fix: line 91 becomes `t.expect((string.find(raftDoc, "f0030", 1, true))).toBe(nil)`. Line 63 should build the source so that it doesn't literally contain `require("`, e.g. `local R = "req" .. "uire"` and then `` `local A = {R}("./A")...` ``. Add a raft RC that simulates promotion: copy each member's acceptance/ into a scratch tests/acceptance/, then run the Lune-definitions luau-lsp stage and tests/meta against it. Alternatively, make `done` run `scripts/check.sh --full` after promotion and before it commits.

### F4 [high] The AC2 workflow spec rejects the idiomatic, correct `workflow_dispatch:`
Where: tracker/issues/c0001/acceptance/ci-workflow.spec.luau:35; c0001 Design, "Triggers"
Evidence: with `@lune/serde`, `serde.decode("yaml", "on:\n  push: ...\n  workflow_dispatch:\n")` yields `on.workflow_dispatch == nil`, because YAML null becomes an absent Lua key. Only `workflow_dispatch: {}` decodes to `{ }`. The usual form (bare key, as in GitHub's docs) therefore fails "is dispatchable". The design doesn't say to write `{}`.
Fix: either state `workflow_dispatch: {}` explicitly in the Design, or change the spec to also accept the raw text: `string.find(text, "\n%s+workflow_dispatch:%s*[\n{]")`.

### F5 [high] AC3 is self-certifying: the executor writes the script that the check trusts
Where: tracker/issues/c0001/check.sh:9
Evidence: `check "AC3: ..." scripts/ci-verify.sh`. ci-verify.sh doesn't exist yet and the executor writes it. A ci-verify.sh that runs `exit 0`, or that watches the wrong run (see F7), passes AC3, and through AC3 also RC0 and `done`. The AC2 spec only proves the YAML shape, e.g. `run: echo scripts/setup.sh` also passes it. So nothing independent proves CI actually went green.
Fix: after ci-verify, have check.sh itself query GitHub, for example `bash -c 'scripts/ci-verify.sh && [[ $(gh run list --workflow check.yml --commit "$(git rev-parse HEAD)" --json conclusion -q "[.[]|select(.conclusion==\"success\")]|length") -ge 1 ]]'`.

### F6 [high] Untested assumption without a fallback: dispatching a feature branch whose default-branch workflow lacks `workflow_dispatch`
Where: c0001 Design, "ci-verify.sh" step 3; Unknowns E1-E3
Evidence: main's check.yml has no `workflow_dispatch` trigger. This raft adds it only on the R0001 branch, which isn't merged until after `done`. GitHub gates workflow_dispatch on the workflow as registered from the default branch. `gh workflow run check.yml --ref R0001-...` can therefore fail with `HTTP 422: Workflow does not have 'workflow_dispatch' trigger`. E3 only asks whether a run appears; nothing tests whether the dispatch is accepted at all. If it is rejected, AC3, RC0 and `done` can never pass, and the raft is BLOCKED with no documented way out.
Fix: add E0, run first: "does `gh workflow run check.yml --ref <branch>` succeed while main lacks the trigger?", with a fallback. Options: have the human land a one-line `workflow_dispatch: {}` change on main before `start`, or let AC3 accept any successful check.yml run for the HEAD sha. The second option is F5's query without `--event`, and can be triggered by a temporary non-draft PR state.

### F7 [medium] ci-verify.sh can watch a stale run for the same HEAD
Where: c0001 Design, "ci-verify.sh" step 4
Evidence: the poll picks the first `workflow_dispatch` run with `headSha == HEAD`. `tracker.sh check c0001`, the raft check.sh and `done` each re-run AC3 on the same HEAD, so earlier dispatches for that sha already exist. The poll matches an old run immediately. If that run failed (a flake or a transient setup error), AC3 can never pass until a new commit. If a newer dispatch fails, AC3 still reports the old success. The E3 fallback (`createdAt` after dispatch) is the correct rule but is only listed as a fallback.
Fix: before dispatching, record the highest existing `databaseId`. Then require a run whose `databaseId` is greater than that and whose `headSha == HEAD`. This avoids clock skew as well.

### F8 [medium] The acceptance specs never run on Linux before `done`
Where: R0001 "Order & dependencies" point 2; c0001 AC3; tracker `done`
Evidence: the raft says "AC3 (CI green) then also proves c0002's place tests pass on Linux". CI runs `check.sh --full`, which collects only `tests/**`. Before `done`, that covers tests/place/structure.spec.luau but none of resolve-require, place-rules, affected-place, tracker-lifecycle or ci-workflow. These specs reach Linux only through the `ready_for_review` run, after `done`, when they are sequestered and permanent. A Linux-only failure (for example, the lifecycle spec's git behaviour on a runner with no global identity, or rojo paths) becomes a post-done defect.
Fix: give the workflow a `workflow_dispatch` input (e.g. `acceptance: true`) that ci-verify.sh sets. With it, CI also runs `lune run tests/run -- $(find tracker/issues/active -path '*/acceptance/*.spec.luau')`.

### F9 [medium] `gh auth status` under the Actions `GITHUB_TOKEN` is asserted, not tested, and has no fallback
Where: c0001 Design, "setup.sh changes": "gh auth status must pass when GH_TOKEN is set (true for gh ≥ 2.x)"; scripts/setup.sh:27
Evidence: setup.sh fails hard (`die "run: gh auth login"`) if `gh auth status` fails. The Actions token is an installation token without `/user` access. Whether `gh auth status` accepts it depends on the gh version, and that hasn't been tried. The E1 fallbacks cover rokit self-install and rate limits, not this.
Fix: fold it into E1 with a fallback: when `CI` is set, check with `gh api rate_limit >/dev/null` instead of `gh auth status`.

### F10 [medium] The lifecycle spec tests the committed HEAD, not the working tree
Where: tracker/issues/c0001/acceptance/tracker-lifecycle.spec.luau:54; c0001 Design, "Tracker lifecycle spec"
Evidence: `git clone -q root dir` copies committed history only. Suppose an agent edits scripts/tracker/*.luau without committing. The Stop hook's `check.sh --affected` selects ALL (because `scripts/` changed), but the spec still exercises the old tracker. A regression passes the local gate and appears only after a commit or in CI. The reverse also happens: a fix doesn't show as green until committed.
Fix: after cloning, overlay the working-tree `scripts/` and `tracker/templates/` into the clone (copy the files that `git ls-files -co --exclude-standard` lists under those paths), then commit them in the clone before the first case.

### F11 [medium] AC3 can be passed by a path-hard-coded selector that misses promoted place specs
Where: tracker/issues/c0002/acceptance/affected-place.spec.luau:22-36
Evidence: the only place spec in the graph is `tests/place/structure.spec.luau`. An `affectedSpecs` rule of "on a src/ or default.project.json change, add every spec under tests/place/" passes all four cases. After `done`, however, `tests/acceptance/c0002/place-rules.spec.luau` and `resolve-require.spec.luau` also depend on `tests/lib/place.luau`, and that rule would never select them for a src change. That is the exact graph miss this spec exists to prevent.
Fix: add a case on a synthetic Graph, for example `{ files = { "x/p.spec.luau", "x/q.spec.luau", "tests/lib/place.luau" }, deps = { ["x/p.spec.luau"] = { "tests/lib/place.luau" }, ["x/q.spec.luau"] = {} }, unresolved = {}, dynamic = {} }`. Assert that a change to `src/client/Foo.luau` selects exactly `{ "x/p.spec.luau" }`.

### F12 [low] "finds the three script roots" doesn't check the roots
Where: tracker/issues/c0002/acceptance/place-rules.spec.luau:9-11
Evidence: the check is `#place.scripts(game) >= 2`. A `scripts()` that walks the whole DataModel, or that ignores the three roots, passes. The case name promises three roots, but src has only two scripts.
Fix: assert that every returned script's `GetFullName()` starts with one of `ReplicatedStorage.Shared.`, `ServerScriptService.Server.` or `StarterPlayer.StarterPlayerScripts.Client.`. Also assert that the list includes `ServerScriptService.Server.Main` and `StarterPlayer.StarterPlayerScripts.Client.Main`.

### F13 [low] The E2 fallback conflicts with setup.sh's existing `.luaurc` restore
Where: c0001 Unknowns E2; scripts/setup.sh:47
Evidence: setup.sh already runs `git checkout -- .luaurc` right after `lune setup`. The fallback says to "generate an absolute-path alias after `lune setup`, then `git checkout -- .luaurc` at the end", but setup.sh's end is the gate itself. An executor has to guess where the rewrite goes, and it must not leave .luaurc dirty on a developer machine (that would break AC4 or `start`'s clean-tree check).
Fix: specify "only when `CI` is set: after line 47, rewrite the alias to `$HOME/.lune/.typedefs/<ver>/`, run the gate, then restore `.luaurc` in an EXIT trap".

Verdict: changes
