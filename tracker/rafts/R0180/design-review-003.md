# Review 003: R0180 (design mode)
Inputs: commit abb9368 (prep worktree `prep-beta-poll-transient-errors`, merged with `origin/main` 55e94b3 at 59d769e, the merge base with `origin/main` is its head); tracker/rafts/R0180/{R0180.md,check.sh,design-review-001.md,design-review-002.md,design-refute-001.md,design-refute-002.md}, tracker/issues/c0490/{c0490.md,check.sh,acceptance/*.spec.luau}, `git diff main...HEAD -- tests/`, `git diff 4c2f248 abb9368 -- tracker/issues/c0490/c0490.md`, tracker/templates/issue/doc.md, and the review, ticket-prep, tracker, testing and architecture skills as merged.
Dropped from design-review-002: F1, F2, F3 (all fixed as design-refute-002 says; checked below).

Verification of the round-2 fixes:
- F1: the Regression guard now has `Overrides: tests/acceptance/c0140/publish.spec.luau (...)`, naming the narrowing (400/401/403/404/429/500/503 to 400/401/403/404), the header-comment edit, and the chore route with no `depends_on`. That matches ticket-prep's Override check ("A chore changes S in its own raft") and the template line. The Solution bullet now points to it.
- F2: Touched modules is `scripts/lib/opencloud.luau` and `.claude/skills/tracker/SKILL.md` only. Affected specs runs the selector on exactly those two paths.
- F3: the header of `tests/acceptance/c0140/publish.spec.luau` now says it retries 409 and, since c0490, transient 429/5xx. Implementation step 1 tells the executor to keep the `opencloud.luau` comments true.

Override check redone (review item 4): `lune run scripts/affected -- scripts/lib/opencloud.luau .claude/skills/tracker/SKILL.md` prints `ALL`. I grepped `tests/acceptance` for the path and the basename. `opencloud` hits c0030/execute, c0030/suite, c0140/config and c0140/publish. `opencloud.luau` has no hits. Only c0140/publish pinned reversed behaviour, and it is named. The c0030 500 cases (`execute.spec.luau:120,135`) feed a repeating 500 through a fake `sleep`, so with retries they still raise naming 500 once `MAX_ATTEMPTS` runs out. `tracker/SKILL.md` and `SKILL.md` hit c0030/pipeline (Merging needles, all still present), c0460/board-docs, c0480/start-depends (the `| start |` row only), c0450/override-check and c0410/* (other skills). Adding one `beta` bullet turns none of them red.

Regression after the merge: c0030 execute/suite/pipeline, c0140 publish/config, c0450 override-check and c0460 board-docs pass on the prep head (39 cases, 7 files). `tracker/issues/c0490/check.sh` gives AC3 and AC8 PASS and the rest FAIL, as in round 2 and as expected before execution. `tracker.sh promote-check R0180` fails today only because `c0490/publish.spec.luau` type-checks `transientBudgetSeconds` against a `Config` that lacks the field. The implementation adds that field, and RC0 runs after it, so this is expected and is not a finding.

No new findings. One cosmetic note, not a finding: the `Overrides:` paragraph sits between two bullets of the Regression guard list. It reads fine and matches the template's placement.

Verdict: approve
