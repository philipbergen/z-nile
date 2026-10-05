# Review 001: R0019 (code mode)
Inputs: HEAD df8393b (diff `origin/main...HEAD`: `scripts/tracker/main.luau`, `scripts/tracker/store.luau`, `.claude/skills/tracker/SKILL.md`, c0052 Verification log); R0019.md, R0019 `check.sh`, c0052.md, c0052 `check.sh`, `acceptance/*.spec.luau`.

Checks run by the reviewer:
- Sequestration: `git diff --find-renames=100% --name-status origin/main...HEAD -- 'tracker/**/check.sh' 'tracker/**/acceptance/**'` lists only `R100` moves to `active/`; `git diff da73e0a HEAD` touches no `check.sh` or acceptance file. Clean.
- `scripts/check.sh --full`: GATE PASSED, 925 passed / 0 failed over 138 spec files, wall time 59.2 s (slowest: c0053/commands 47.4 s, already filed as c0062).
- `scripts/tracker.sh check c0052`: 3/3 (AC1 to AC3).
- `scripts/tracker.sh promote-check R0019`: OK. RC1: the usage shows `renumber <old> [<new>]`.

How it interacts with c0053:
- **Publishing.** `renumber` stays local. It doesn't publish, and it's still refused in the main checkout (the guard is still the first statement). With publishing on, `new` gives ids to origin/main as multiples of 10 (`statusLib.nextNumber`), so a number from `renumber` (max+1, not a multiple of 10 unless max+1 happens to be one) can only collide with another concurrent renumber. The design puts that out of scope. An ordinary `new` still lands at the next multiple of 10 above it (new-spacing spec).
- **Status.** `renumber` leaves `status:` alone. It moves the directory and rewrites references, as it did before. In a real add/add clash, the old id is by definition on origin/main (it belongs to the other item), and the renamed item is the local-only one (PICKMAN_PUBLISH=0, or a cutover prep). So origin's status records aren't orphaned by renumbering "your own" item.
- **`originIds`.** c0053's `originIds(kind)` fetches and returns `{}` when publishing is off or the read fails. That would silently undercount for `renumber`, so a separate reader that doesn't fetch and refuses on failure (`originMainIds`) is the right behaviour. The rename is recorded in the Verification log, and argument order makes `store.get(old)` fail before any git read. One maintainability note is below (F1).

### F1 [low] Two adapters read origin/main's tracker ids with different listings, and they can drift apart
Where: `scripts/tracker/main.luau:269` (`originIds`) and `scripts/tracker/main.luau:758` (`originMainIds`)
Evidence: `originIds` runs `git ls-tree -r --name-only --full-tree origin/main tracker/` and takes ids from file paths (`idsOf`). `originMainIds` runs `git ls-tree -d --name-only origin/main` over six hard-coded `{issues,rafts}/{"",active/,done/}` paths (relative to the cwd, without `--full-tree`) and takes basenames. The state-directory list is also hard-coded in `store` (`STATE_DIRS`) and in `cmd.migrate`. Suppose a fourth state directory is added. `new` would see it through `-r`, but `renumber` wouldn't until someone edits `originMainIds` too, and no spec would notice.
Critique: their behaviours really do differ (fetch and swallow failures for `new`, no fetch and refuse for `renumber`), so the tempting fix of merging them into `originIds` would undercount silently. Only the listing should be shared.
Consequences: a shared listing helper has to keep the "fails loudly" result for `renumber`, so it returns `ok` plus the ids, and `new` keeps its own fallback to `{}`. That doesn't change behaviour, and the existing specs cover both callers (c0052 `renumber.spec` M5/M6; c0053 `status.spec` next-number case).
Recommendation: optional, and it can be a follow-up chore. Build one listing helper on `ls-tree -r --full-tree origin/main tracker/` plus `idsOf` that returns `(ok, ids)`. `originIds` keeps fetch-then-fallback, and `originMainIds` keeps no-fetch-and-refuse. It shouldn't block this PR.

## Judged criteria (code mode only)
None.

Verdict: approve
