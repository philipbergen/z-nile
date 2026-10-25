# Response to design-review-001

- F1: fixed: RC1 now requires at least one `tests/place` spec file, and a missing or empty directory fails. The raft doc's command has been corrected.
- F2: fixed: `.luaurc` now has the `@scripts` alias, landed on main in prep and recorded in c0002's Design. Cause: running c0001's AC4 (`setup.sh`) during prep restored the committed `.luaurc` over the uncommitted alias. The testing and architecture skills now list `@scripts`.
- F3: fixed: the lifecycle spec's `string.find` result is wrapped in parentheses. resolve-require builds its require text by concatenation. In the tooling, `done` now requires a clean tree; after promotion it type-checks `tests/`, runs `tests/meta` and the promoted specs, and rolls back on failure. The lifecycle spec pins that path with the new "rolls back" case. The testing skill forbids literal `require("…")` text in strings.
- F4: fixed: the ci-workflow spec accepts either `workflow_dispatch: {}` or the bare key (checked on the raw text). Main uses `{}` and the design says so.
- F5: fixed: c0001's AC3 now also checks independently for a successful `workflow_dispatch` run of `check.yml` for HEAD's sha, using `gh run list --commit`.
- F6: fixed: resolved by experiment E0 in prep. `workflow_dispatch: {}` and the draft-only `if:` condition landed on main, and a probe branch was dispatched successfully (run 36511379058, then deleted).
- F7: fixed: ci-verify.sh records the highest `databaseId` before dispatching and requires a newer run with the same `headSha`.
- F8: fixed: the workflow gets a dispatch-only step that runs `tracker/**/active/*/acceptance/*.spec.luau`, pinned by a new case in the ci-workflow spec. The raft's Order section explains it.
- F9: fixed: when `CI` is set, setup.sh checks auth with `gh api rate_limit` (in c0001's Design, under E1).
- F10: fixed: the lifecycle spec overlays the working tree's `scripts/` and `tracker/templates/` into the clone before its first case.
- F11: fixed: a synthetic-graph case requires selection by dependency on `tests/lib/place.luau`, not by directory. c0002's Design states the rule.
- F12: fixed: place-rules asserts that every script lies under the three roots, and that both Main scripts are present.
- F13: fixed: E2 is resolved (PASS on Linux CI), and the regression fallback specifies exactly where the rewrite goes, with an EXIT-trap restore.
