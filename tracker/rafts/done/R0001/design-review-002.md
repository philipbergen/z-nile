# Review 002: R0001 (design mode)
Inputs: commit f33e77f (main, clean). Files: R0001-foundation.md, R0001/check.sh, design-review-001.md, design-refute-001.md, c0001 and c0002 docs, check.sh files and acceptance/*.spec.luau, scripts/ (check.sh, setup.sh, tracker.sh, affected.luau, lib/*, tracker/*), tests/, .github/workflows/check.yml, .luaurc, SETUP.md, and the skills. Experiments: `scripts/check.sh --full` on main (green, 20 specs); `tracker.sh check c0002` (all 3 ACs fail for the right reason: no place.luau and no PLACE_LIB); c0001 AC1/AC2 specs (lifecycle 9/9 pass; ci-workflow fails only the 3 not-yet-built cases); the RC1 command on main (exit 1, correct); the AC3 bash with a stubbed ci-verify, against a known dispatch sha (exit 0) and against HEAD (n=0, exit 1), so the quoting is correct; a promotion simulation in .cache/rv2 (both acceptance dirs copied to tests/acceptance/<id>, plus a stub place.luau typed as designed and `graph.PLACE_LIB`); a design-conformant check.yml fed to the ci-workflow spec; `rokit authenticate --help` and the rokit binary's strings.

Round-1 findings, re-checked:
- F1, F2, F4, F6, F7, F9, F10, F11, F12 and F13 are resolved. I've dropped them.
- F3 is only half fixed: part (a) is fixed, part (b) is not. It's re-raised as F1 below.
- F5 fixed the self-certification of ci-verify.sh, but not the AC2 half. That's re-raised as F4.
- F8 is fixed in intent, but the new step fails as written. See F2.

### F1 [high] The promoted resolve-require spec still breaks tests/meta, so `done` will roll back and the raft can't finish without editing a sequestered spec
Where: tracker/issues/c0002/acceptance/resolve-require.spec.luau:63; tests/meta/architecture.spec.luau:44-50; scripts/tracker/main.luau:415-427
Evidence: the F3(b) fix moved the literal out of the source string, but it left it in the comment on the line above: `-- built by concatenation so this file itself contains no literal require("...") text`. graph.luau:112 matches `require("...")` in comments too, so `...` becomes an unresolved require. In .cache/rv2, after promotion, `luau-lsp analyze ... tests` exits 0. But `lune run tests/run -- tests/meta/architecture.spec.luau` gives `FAIL every require resolves: expected "", got "tests/acceptance/c0002/resolve-require.spec.luau: require(\"...\")"`. `done` runs exactly that meta spec after promotion, so the raft's last step fails every time and rolls back. The executor may not edit the spec (execute-raft: stop and escalate). Nothing earlier in the raft catches this. The spec sits in tracker/, which the meta graph doesn't scan, and no RC simulates promotion. So the problem appears only after all the CI and review work is finished.
Fix: in prep, reword the comment, e.g. `-- built by concatenation so this file contains no literal require-call text`. To catch the whole class earlier, add a raft RC that runs `graph.build` over `tracker/issues/active` and fails on any unresolved spec that isn't produced by the raft's own new files. Alternatively, have RC0 run the meta rule over `tracker/**/acceptance`.

### F2 [medium] The dispatch-only acceptance step runs without `~/.rokit/bin` on PATH, so c0002's place-rules spec can't find `rojo` in CI
Where: c0001 Design, Steps 3 (the YAML block); c0002 Design, `place.load()` ("Builds default.project.json with `rojo build`")
Evidence: setup.sh's `export PATH="$HOME/.rokit/bin:$PATH"` only affects setup.sh's own process. GitHub's default `bash -e {0}` shell doesn't source the profiles that `rokit self-install` edits. The rokit binary contains no `GITHUB_PATH` handling (`strings ~/.rokit/bin/rokit | grep GITHUB_PATH` is empty). The design knows this, because it calls `~/.rokit/bin/lune` by absolute path. But `place.load()` runs `rojo build` at module load (place-rules.spec.luau:6). Under that step, `process.exec("rojo", …)` gets no such file, so the whole spec file fails to load. The dispatch run goes red and AC3 fails for an environment reason. (The lifecycle spec is unaffected because tracker.sh exports PATH itself.)
Fix: make the step start with `export PATH="$HOME/.rokit/bin:$PATH"` and call plain `lune`. Or have setup.sh run `[ -n "${GITHUB_PATH:-}" ] && echo "$HOME/.rokit/bin" >> "$GITHUB_PATH"` when CI is set. State this in c0001's Design.

### F3 [medium] `rokit authenticate github --token "$GH_TOKEN"` with the Actions token is an untested assumption with no fallback
Where: c0001 Design, "`scripts/setup.sh` changes", Rokit rate limits; Unknowns E1
Evidence: rokit 1.2.0 validates tokens in two ways. It parses the format (the binary's strings include `unrecognized access token format - must begin with \`ghp_\` or \`gho_\``, and "Starting with 'gh' followed by a lowercase letter and an underscore"). It also verifies them live ("GitHub API returned an error during token verification"), and offers `--skip-parse` and `--skip-verify` to bypass these. `GITHUB_TOKEN` is a `ghs_` installation token, and the same `/user`-style verification is exactly what F9 avoided for `gh auth status`. If either check rejects it, `set -e` aborts setup.sh, so CI goes red on every run. E1's fallbacks cover self-install and rate limiting, but not a rejected authenticate.
Fix: add to E1: "if `rokit authenticate` rejects the token, retry with `--skip-parse --skip-verify`; if that still fails, drop the step (anonymous limits suffice for 5 tools)". Or specify `--skip-verify` from the start.

### F4 [medium] AC2 and AC3 both pass with a workflow that never runs the gate
Where: tracker/issues/c0001/acceptance/ci-workflow.spec.luau:15-25; tracker/issues/c0001/check.sh:9-11
Evidence: I fed the ci-workflow spec a design-conformant check.yml with the setup step changed to `- run: echo skipping scripts/setup.sh` (GH_TOKEN env kept). It reported `5 passed, 0 failed`. That workflow then finishes green in seconds, so AC3's independent `gh run list … conclusion == success` query also passes. The same holds for plausible "temporary" edits made while fighting E1: `scripts/setup.sh || true`, or `continue-on-error: true` on the step. So "CI is green for HEAD" doesn't imply that the gate ran on Linux, which is the whole point of c0001. The round-1 F5 evidence already named `run: echo scripts/setup.sh`; the fix addressed only ci-verify.sh.
Fix: in the spec, require the setup step's trimmed `run` to equal `scripts/setup.sh`, and require no `continue-on-error` on any step. Or, more robustly, extend AC3 to check the run's log for the gate's own output: `gh run view <id> --log | grep -q "GATE PASSED (full)"`, with the id taken from the same `gh run list --commit` query.

### F5 [low] `done` books the promoted acceptance specs as execution spend, split across issues that didn't write them
Where: scripts/tracker/main.luau:436; scripts/tracker/spend.luau:21
Evidence: `stagedStats` excludes `tracker/` only on the source side. A rename from `tracker/issues/active/<id>/acceptance/` to `tests/acceptance/<id>/` therefore counts as newly added lines. In the lifecycle clone, the done commit reads `Issue: f0010 +4/-0` and `Issue: f0031 +4/-0`: the 8-line fixture spec is split evenly, and f0031 owns no acceptance spec at all. For R0001, that's about 490 prep-written lines credited to execution. For feature rafts, it inflates feature lines and so understates rework %.
Fix: in `done`, record the promotion with zero lines (e.g. compute stats with `--find-renames` and skip pure renames, or exclude `tests/acceptance/` from the done commit's stats).

### F6 [low] The lifecycle spec contains literal require text inside a string, against the rule the refutation added to the testing skill
Where: tracker/issues/c0001/acceptance/tracker-lifecycle.spec.luau:150
Evidence: `'--!strict\nlocal t = require("@tests/lib/t")\n…'`. The graph scanner records it as a real dependency. It happens to resolve (to tests/lib/t.luau, which the spec requires anyway), so the meta spec passed in the rv2 simulation. It's still the pattern that produced F1, and it contradicts the testing skill's "never write literal `require("…")` text inside strings or comments".
Fix: build it with the same `"req" .. "uire"` concatenation used in resolve-require.

### F7 [low] c0001's Implementation steps omit the auth change in setup.sh
Where: c0001 Implementation steps 1-2 vs Design, "`scripts/setup.sh` changes", Auth
Evidence: step 2 says only "Add the `rokit authenticate` step". The switch from `gh auth status` to `gh api rate_limit` under CI (the F9 fix) appears only in the Design. An executor who follows the steps literally keeps setup.sh:27 unchanged, and E1 may fail on the first dispatch.
Fix: step 2 becomes "In setup.sh, when `CI` is set: `gh api rate_limit` for the auth check, and `rokit authenticate` before `rokit install`."

Verdict: changes
