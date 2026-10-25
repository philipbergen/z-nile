# Review 003: R0018 (design mode)
Inputs: commit abb9368 (prep worktree `prep-beta-poll-transient-errors`, merged with `origin/main` 55e94b3 at 59d769e, the merge base with `origin/main` is its head); tracker/rafts/R0018/{R0018.md,check.sh,design-review-001.md,design-review-002.md,design-refute-001.md,design-refute-002.md}, tracker/issues/c0051/{c0051.md,check.sh,acceptance/*.spec.luau}, `git diff main...HEAD -- tests/`, `git diff 4c2f248 abb9368 -- tracker/issues/c0051/c0051.md`, tracker/templates/issue/doc.md, and the review, ticket-prep, tracker, testing and architecture skills as merged.
Dropped from design-review-002: F1, F2, F3 (all fixed as design-refute-002 says; checked below).

Verification of the round-2 fixes:
- F1: the Regression guard now has `Overrides: tests/acceptance/c0015/publish.spec.luau (...)`, naming the narrowing (400/401/403/404/429/500/503 to 400/401/403/404), the header-comment edit, and the chore route with no `depends_on`. That matches ticket-prep's Override check ("A chore changes S in its own raft") and the template line. The Solution bullet now points to it.
- F2: Touched modules is `scripts/lib/opencloud.luau` and `.claude/skills/tracker/SKILL.md` only. Affected specs runs the selector on exactly those two paths.
- F3: the header of `tests/acceptance/c0015/publish.spec.luau` now says it retries 409 and, since c0051, transient 429/5xx. Implementation step 1 tells the executor to keep the `opencloud.luau` comments true.

Override check redone (review item 4): `lune run scripts/affected -- scripts/lib/opencloud.luau .claude/skills/tracker/SKILL.md` prints `ALL`. I grepped `tests/acceptance` for the path and the basename. `opencloud` hits c0003/execute, c0003/suite, c0015/config and c0015/publish. `opencloud.luau` has no hits. Only c0015/publish pinned reversed behaviour, and it is named. The c0003 500 cases (`execute.spec.luau:120,135`) feed a repeating 500 through a fake `sleep`, so with retries they still raise naming 500 once `MAX_ATTEMPTS` runs out. `tracker/SKILL.md` and `SKILL.md` hit c0003/pipeline (Merging needles, all still present), c0048/board-docs, c0050/start-depends (the `| start |` row only), c0047/override-check and c0043/* (other skills). Adding one `beta` bullet turns none of them red.

Regression after the merge: c0003 execute/suite/pipeline, c0015 publish/config, c0047 override-check and c0048 board-docs pass on the prep head (39 cases, 7 files). `tracker/issues/c0051/check.sh` gives AC3 and AC8 PASS and the rest FAIL, as in round 2 and as expected before execution. `tracker.sh promote-check R0018` fails today only because `c0051/publish.spec.luau` type-checks `transientBudgetSeconds` against a `Config` that lacks the field. The implementation adds that field, and RC0 runs after it, so this is expected and is not a finding.

No new findings. One cosmetic note, not a finding: the `Overrides:` paragraph sits between two bullets of the Regression guard list. It reads fine and matches the template's placement.

Verdict: approve
