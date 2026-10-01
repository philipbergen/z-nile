# Review 001: c0360 (stream mode)
Inputs: `git diff R0130-tracker-hardening...ws-c0360` (c59aecf, b5a162b), c0360.md, check.sh, acceptance/deferred.spec.luau.

Checks run: `scripts/tracker.sh check c0360` 3/3 PASS (AC1 and AC2 exercise the spec's cases); `luau-lsp analyze`, `selene --quiet` and `stylua --check` clean on the final tree. The full gate and a separate spec run were not repeated by me; the implementer's log reports `check.sh --full` passed.

Scope: the diff touches only `scripts/tracker/main.luau`, the two skills and c0360.md. No `check.sh`, acceptance spec or `architecture.md` change. `cmd.done`, `runCheck` and `refuseListMode` are untouched (hunks are inside `reviewProblem` only). `tests/acceptance/c0360` does not exist yet (promoted at done), which is expected. The Verification log entry is self-contained.

Design adherence: `fixed`/`refuted` unchanged and accepted first; `deferred` only as the word alone or followed by whitespace; the target pattern matches the Design; severity read from the heading line only, lowercased, unrated and high refused with the specified wording; the target must be a backlog issue (`kind == "issue"`, `state == "backlog"`); unanswered findings are returned before invalid deferrals, with the existing message. Skills: execute-raft step 7 has `- F<n>: deferred <id>: <why>` and neither `interim form` nor `refuted: below the merge threshold`; the tracker `done` row mentions `deferred <id>`.

No findings. The only observation is that case-insensitive severity has no spec case (the design records it as reasoned, one `string.lower`).

Verdict: approve
