# Review 001: c0060 (stream mode)
Inputs: `git diff R0130-tracker-hardening...ws-c0060` (commit d09be76), `tracker/issues/active/c0060/c0060.md`, `check.sh`, `acceptance/changed.spec.luau`. Run in the stream worktree: `scripts/tracker.sh check c0060` (3/3 pass), `scripts/check.sh --affected` (selected all specs because `scripts/` changed: 454 passed, 0 failed, 73 spec files, GATE PASSED; stylua, selene, luau-lsp and rojo clean).

Scope: the diff touches only `scripts/lib/changed.luau`, `scripts/affected.luau` and the issue document (one Verification log line). No `check.sh`, acceptance spec or `tracker/architecture.md` change. Design adherence: module path and signature `changed.files(base: string?, cwd: string?)` match; `affected.luau` uses `local changes = require("./lib/changed")` and `changes.files(base)`; the private `git` helper and `changedFiles` are gone (no other users of `process` were broken: it is still used for args). The body is a faithful copy with `cwd` passed through `process.exec`; ordering and silent-failure semantics are unchanged. I found no behavioural defect.

### F1 [low] Verification log entry is not a self-contained record
Where: `tracker/issues/active/c0060/c0060.md`, Verification log (the one added line)
Evidence: the entry ends "acceptance spec 9/9, affected spec, check c0060 and full gate run (see report)". "See report" points at a transient agent report that is not in the repository. The entry also gives no result for "affected spec", "check c0060" or "full gate", only the 9/9 figure.
Critique: the log is the durable record of what was run and what came of it; a reader of the PR cannot verify the claim. The tempting fix is to paste a link to the report, which has the same problem.
Consequences: none beyond rewriting the line; the lead's merge and `tracker.sh done` do not parse it.
Recommendation: replace "(see report)" with the commands and results, for example: `lune run tests/run -- tests/acceptance/c0060/changed.spec.luau` 9/9; `tests/tooling/affected.spec.luau` N passed, 0 failed; `scripts/tracker.sh check c0060` 3/3 criteria passed; `scripts/check.sh --full` GATE PASSED with the counts. Note any deviation, or "no deviations".

Verdict: approve
