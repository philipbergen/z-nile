# Review 001: R0022 (code mode)
Inputs: HEAD 34e8789 (`git diff origin/main...HEAD`, start commit fa11468); R0022.md, R0022 check.sh; c0057.md, c0057 check.sh, acceptance/open.spec.luau, acceptance/guard.spec.luau; tests/run.luau, scripts/tracker/main.luau, tests/tooling/board.spec.luau, .github/workflows/board.yml, tracker and testing skills.

Runs (by the reviewer, one at a time): `scripts/check.sh --full`: GATE PASSED (744 passed, 0 failed, 118 spec files, 20.5 s). `scripts/tracker.sh check c0057`: 9/9 PASS. Sequestration: `git diff fa11468 -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` is empty. Afterwards the tree is clean.

Correctness notes (no finding):
- `cmd.board` matches the Design step by step: the argument check comes first, then the contradiction check before any write, then write and print, and the opener runs when `-O` is absent. The `USAGE` and skill texts match the Design exactly. `board.yml` has a trailing `-O`.
- `-O` is now a global boolean in `flags()`. No other command reads `-O`. The one behaviour change elsewhere is that `tracker.sh <cmd> -O x` now leaves `x` positional where `-O` used to swallow it. That is harmless and was noted in Maintainability.
- Guard: workers (`lune run tests/run -- --jobs 1 file`) and nested runners started by specs inherit `PICKMAN_OPEN_GUARD`, because Lune's `env` merges. This includes `run-lane-error`, which replaces `PATH` with `/usr/bin:/bin` but keeps the marker, so it runs nested with no re-exec. Every opener call therefore lands in one log, and exit codes are passed through unchanged. The re-exec uses the relative `tests/run`, the same assumption the worker path already makes.
- The two promoted overrides and R0020's c0053 spec carry a trailing `-O`, as the prep states. No other spec in `tests/` runs `board`.

### F1 [low] The outermost runner now needs `lune` on PATH even in in-process mode, and leaks its guard directory when that re-exec fails
Where: tests/run.luau:42-71 (`process.exec("lune", args, …)` without `pcall`, and `fs.removeDir(dir)` only on the normal path)
Evidence: `env -u PICKMAN_OPEN_GUARD PATH=/usr/bin:/bin:/usr/sbin ~/.rokit/bin/lune run tests/run -- tests/acceptance/c0048/board-workflow.spec.luau` dies with a raw Lune error, `No such file or directory (os error 2)` at `tests/run` line 59, and exits 1. A fresh `tmp.*` directory holding the `open`/`xdg-open` stubs is left in `$TMPDIR`. Two such directories from this review's probes are still there; the reviewer's sandbox refused to delete them, so the user may want to. Before this change, a single-file or `--jobs 1` run was fully in-process and never spawned `lune`. The worker spawn already wraps `process.exec("lune", …)` in `pcall` (tests/run.luau:147) for this case (c0049 review F1). Ctrl-C during a run also leaves the directory, because the parent dies before `removeDir`.
Critique: this is a narrow case. Normal setups have `lune` on PATH, and the gate, the hook and `ac.sh` all do. But the result is an unexplained stack trace, where the runner's own convention is a one-line message. The tempting fix is a `pcall` around the re-exec that prints a message and exits.
Consequences: the `pcall` needs a cleanup of `dir` on the error path too, or the leak stays. If the fallback on failure were to run in-process unguarded, the guard could be bypassed silently by a missing PATH entry, so failing is the right result. Ctrl-C can't be handled in Lune, so that leak stays: the directories are tiny and live in `$TMPDIR`.
Recommendation: wrap the re-exec in `pcall`. On failure, `fs.removeDir(dir)`, write `tests/run: could not re-run under the browser guard (is lune on PATH?): <err>` to stderr, and exit 1. One tooling case can pin it: run the runner by absolute path with the marker unset and `PATH=/usr/bin:/bin:/usr/sbin`, then expect exit 1, the message on stderr, and no new stub directory. This is optional for this PR: it can be a follow-up chore.

## Judged criteria (code mode only)
None.

Verdict: approve
