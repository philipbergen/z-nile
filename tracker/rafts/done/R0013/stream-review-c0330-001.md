# Review 001: c0034 (stream mode)
Inputs: `git diff R0013-tracker-hardening...ws-c0034` (6 files), c0034.md, check.sh, acceptance/locator.spec.luau.

Checks run (hard-limited, own process group): `scripts/tracker.sh check c0034` 5/5; acceptance spec 8 passed, 0 failed; `scripts/check.sh --full` 454 passed, 0 failed, GATE PASSED. Spot checks: `AC_LIST=1 scripts/tracker.sh check c0034` refuses; `AC_LIST= bash tracker/issues/done/c0044/check.sh` (empty value) runs normally 11/11 (no bypass, no behaviour change); `AC_LIST=0 lune run tests/run` refuses (any non-empty value is list mode, as designed; fails closed). The only `tests/run` process left running belongs to another session's unrelated shell command, not this stream.

Scope: the diff touches only ac.sh, tests/run.luau, main.luau, tracker/templates/issue/check.sh (Touched module `tracker/templates/issue`), the testing skill and c0034.md. No issue/raft `check.sh`, acceptance spec, repaired done `check.sh` or `architecture.md` changed. `refuseListMode()` is defined after `process` and `fail` and called from `runCheck` and the very top of `cmd.done`; no other part of `cmd.done` was touched. ac.sh matches the Design exactly (LIST label, `---- n criteria listed (none run)`, return 0, empty script still fails before the list branch, unchanged without AC_LIST). The template header, rule comment, skill example and the `Work outside` + `check` sentence match the Design and the AC5 greps. The Verification log entry is self-contained (before/after counts, commands, results; no "see report").

No findings.

Verdict: approve
