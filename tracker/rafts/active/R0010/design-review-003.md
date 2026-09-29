# Review 003: R0010 (design mode)
Inputs: commit a4b78a7 (main, clean). Files: R0010-foundation.md, R0010/check.sh, design-review-001/002.md, design-refute-001/002.md, c0010 and c0020 docs, check.sh files and acceptance/*.spec.luau, scripts/ (check.sh, setup.sh, tracker.sh, affected.luau, lib/*, tracker/*), tests/, .github/workflows/check.yml, .luaurc, default.project.json, the skills and tracker/templates/raft/check.sh. Experiments:
- `scripts/check.sh --full`: green, 21 passed, 4 spec files.
- c0010 AC1/AC2 specs: 11 passed, 3 failed. Only the 3 not-yet-built workflow cases fail.
- `tracker.sh promote-check R0010`: fails only on the missing `@tests/lib/place` and `graph.PLACE_LIB`, as expected, and leaves a clean tree.
- `rokit authenticate --help`: both skip flags are present.
- Scratch scripts in .cache/rv3: comment stripping compared with the raw scan over every .luau file in src, tests, scripts and tracker; stripComments edge cases; a modified check.yml fed to a copy of the ci-workflow spec.

Round-2 findings, re-checked:
- **F1**: resolved. The comment was reworded, and `promote-check` exists and is wired into RC2, the raft template, execute-raft Phase 3 and ticket-prep. I compared stripping against the raw scan over every existing file. The resolved require specs are identical everywhere, except that graph.luau's own `{x}` comment is dropped, which was filtered anyway. So no existing file loses a real require today. The new stripper does have its own soundness hole, raised as F1 below.
- **F2, F3, F6 and F7**: resolved. Dropped.
- **F4**: only half fixed. The `echo … scripts/setup.sh` bypass is closed, but the `continue-on-error` bypass named in round 2 is not. Re-raised as F2.
- **F5**: resolved for the done commit. It introduces a smaller side effect (F4 below).

### F1 [medium] `graph.stripComments` can silently drop real requires across many lines, so the meta rules and `affected` under-report
Where: scripts/lib/graph.luau:104-111 (the function, and its comment "can only hide requires that follow it on the same line")
Evidence: with `R = "req".."uire"`, `.cache/rv3/edge.luau` gives:
- `---[[\nlocal A = R("./A")\n--]]\n` (the common Lua comment-toggle idiom, where `---[[` is a *line* comment and the code is live) → no specs found. The block pattern matches `--[[` starting at the second dash and strips the live code.
- `local banner = "--[[ x"\nlocal A = R("./A")\nlocal B = R("./B")\nlocal z = t[i[1]]\nlocal C = R("./C")\n` → only `./C` is found. The `--[[` inside a string swallows every line up to the next `]]`, which here is an ordinary nested index.
- `local s = "a--b"; local A = R("./A")` → nothing is found (this case is documented).
A real require hidden like this disappears from `g.deps` and `g.unresolved`. The effects:
- tests/meta's "every require resolves" rule no longer sees it;
- "features are only used through their init.luau" and "cross-feature requires are declared" pass for a real violation;
- `affected` skips the dependent specs.
Before round 2 the scanner over-reported, which was loud. Now it under-reports silently. The in-code comment also claims only same-line damage is possible, which is false. The one new test covers only real comments.
Fix: strip with a small left-to-right scanner that skips string literals (`'…'`, `"…"`, `` `…` ``, `[=*[…]=*]`) and treats `--` as a comment only outside strings. `--[=*[` opens a block only when it starts the comment, so `---[[` stays a line comment. Add the three cases above to tests/tooling/affected.spec.luau. If that's too much for prep, at least fix the `---[[` case: require the block opener not to be preceded by `-`. Then correct the comment.

### F2 [medium] AC2 and AC3 still pass with a workflow whose gate failure is ignored (`continue-on-error`)
Where: tracker/issues/c0010/acceptance/ci-workflow.spec.luau:15-28; design-refute-002 F4
Evidence: I copied the ci-workflow spec, pointing it at `.cache/rv3/wf/.github/workflows/check.yml`, a design-conformant workflow (exact `run: scripts/setup.sh` with `GH_TOKEN`, plus the dispatch acceptance step) with `continue-on-error: true` added to **both** steps. Result: `5 passed, 0 failed`. On GitHub, a failed step with `continue-on-error: true` leaves the job, and the run's `conclusion`, at `success`. AC3's `gh run list … select(.conclusion == "success")` then passes too. So "CI green for HEAD" still doesn't imply that the gate or the acceptance specs passed on Linux. The refutation's premise ("a green run implies the gate passed") doesn't hold for this workflow. It's exactly the "temporary" edit an executor fighting E1 (rokit on Ubuntu) would make, and round 2 named it explicitly.
Fix: add one case to the spec: no step and no job has a truthy `continue-on-error`. The more robust alternative is to have AC3 grep the dispatched run's log for `GATE PASSED (full)`, using `gh run view <id> --log`.

### F3 [low] `withPromotedCopies` doesn't clean up if the check throws or is interrupted, and the next `tracker.sh commit` commits the copies
Where: scripts/tracker/main.luau:346-370
Evidence: the copies are removed only after `check(copied)` returns. `process.exec` raises an error, rather than returning `ok=false`, when a binary can't be spawned. A Ctrl-C, or an agent tool timeout during the analyze-and-meta run (several seconds), also kills the process first. In each case `tests/acceptance/<id>/` is left behind as untracked copies. `tracker.sh commit` runs `git add -A` and commits them. After that:
- `withPromotedCopies` sees the directory as tracked, and skips both copying and removal. promote-check then silently tests a stale copy.
- At `done`, `git mv tracker/issues/active/<id>/acceptance tests/acceptance/<id>` moves into the existing directory and produces `tests/acceptance/<id>/acceptance/…`.
- The sequestration diff (`tracker/**`) doesn't see any of it.
Fix: wrap the call as `local okCall, ok = pcall(check, copied)`, always run the cleanup loop, and then re-raise if `okCall` is false. Optionally, make promote-check fail if `tests/acceptance/<id>` is already tracked while the raft is active.

### F4 [low] The spend exclusion of `tests/acceptance` is permanent, and the tracker skill doesn't mention it
Where: scripts/tracker/spend.luau:21-28; .claude/skills/tracker/SKILL.md "Spend: Lines: the staged diff, excluding `tracker/`"
Evidence: `:(exclude)tests/acceptance` applies to every commit, not just `done`'s promotion. The testing skill says a wrong promoted spec is handled by filing a defect. That defect's changes to `tests/acceptance/<id>/…` are recorded as +0/-0, which understates the lines-based rework %. The tracker skill still documents only the `tracker/` exclusion.
Fix: exclude only in the done commit, e.g. with a parameter to `stagedStats`, or by skipping pure renames whose source is under `tracker/`. Update the skill's Spend bullet to match.

### F5 [low] `place.requireSpecs` "same pattern as graph.luau" is now ambiguous about comments
Where: c0020 Design, `place.requireSpecs`; tracker/issues/c0020/acceptance/place-rules.spec.luau (last case)
Evidence: since round 2, graph scans *comment-stripped* source. If requireSpecs copies only the pattern, a commented-out require in `src/` fails AC2 ("does not resolve in the DataModel") while tests/meta passes. If requireSpecs reuses `graph.stripComments`, it inherits F1. The acceptance case has no comments, so either choice passes.
Fix: state in the Design that `requireSpecs(source)` scans `graph.stripComments(source)`, and so shares graph's semantics and any F1 fix.

## Executability
Apart from the points above, a no-context agent can follow the documents to `tracker.sh done` without asking:
- the order (c0020, then c0010), the RC0–RC2 commands and the promote-check escalation point are all explicit;
- every E1–E3 fallback is spelled out;
- dispatch uses the branch's workflow file, and main already has `workflow_dispatch: {}`;
- after setup.sh's `GITHUB_PATH` export, the CI acceptance step finds both `lune` and `rojo`.

Verdict: changes
