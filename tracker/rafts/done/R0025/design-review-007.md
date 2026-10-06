# Review 007: R0025 (design mode)
Inputs: prep-ready-raft at 671fd02. Read: the c0072 and c0073 documents, `check.sh` files and acceptance specs; `design-review-006.md` and `design-refute-006.md`; `R0025.md` and its `check.sh`; the c0070 design and its board-refresh spec (for fit); R0021 at origin/R0021-check-isolation a4ea342 (`fixture.luau`, `fence.luau`, `fence.sh`, the `repo-fence.spec` NAMES and sources, the c0060 retrofit scan, the `guarded()` change to `publishing()`).

Spot checks:
- **history.spec fixture.** I rebuilt it in a scratch repository, with the same commits and dates, and ran it with the exact `LOG_ARGS`. In git's real output:
  - c0003's ready move prints the add before the delete. Its stop move prints the delete before the add (`active/` sorts first). Every move carries `-status`/`+status` lines with the old and new values.
  - The c0006 migration is a delete plus an add inside `done/c0006/`.
  - c0004 is a pure add into `done/`.
  - Recomputed by hand from that output: c0003 prepared 0.5 + 0.5 (n=2), active 0.5 + 1.0 (mean and median 0.75), closed 2026-10-05. c0004 closed 2026-10-02. c0006 closed 2026-10-03 (not 10-04). f0010's and c0002's spells are unchanged. Today is 2026-10-05.
- **Close days on the real repository.** On this repository, `LOG_ARGS` writes 4,138,676 bytes. The first-add-into-`done/` rule gives a close day to all 50 `done/` issues. All 7 adds into `done/` that carry a status line are moves with an unchanged status.
- **board-stats.** The month window for 2025-06-12 is 32 days. `collect(tree .. "/tracker")` reads history from `.cache/c0073-board`, which has no git: the fence's `GIT_CEILING_DIRECTORIES` stops the search at `.cache`, and without the fence `show-toplevel` is the real root, which isn't that directory.
- **land.spec.** I traced every sub-case of "refuses anything but…" against the fixture state:
  - the stub's `check.sh` exists because `new` publishes it;
  - the spec's own merge of `origin/main` is a no-op, so `HEAD~1` after each reset is the capture commit;
  - each sub-case's diff holds its offending path plus the allowed capture `M`.
- **The race gate.** The first push is rejected deterministically, because land's `origin/main` was fetched before the gate pushed. `git push origin <sha>:refs/heads/main` updates `refs/remotes/origin/main`, which I checked in a scratch repository. That makes c0070's `merge --ff-only origin/main` in the main checkout work after land.
- **Both `check.sh` files.** They pass `bash -n` with /bin/bash 3.2, and `AC_LIST=1` lists 5 and 7 criteria. AC5's `\bPR\b` matches as intended in BSD grep 2.6.0. No member spec names anything from R0021's NAMES list.
- **c0048.** Only its "has exactly four steps" case pins `steps[1]`, and the Overrides line names that case. c0015's checkout assertions are on other workflows.

Every fix in refute 006 is in the documents and specs and works: F1, F2, F3, F5, F6, F7, F8, F9, F10, F11 and F12. F4's fix is in place, but it leaves the two gaps below.

### F1 [high] land's draft rule reads only `origin/main`'s copy, so a capture can push its own issue as `design: ready` (and with any `status:`), skipping ticket-prep
Where: c0072 Design step 3 ("an `M` is allowed only while `origin/main`'s copy says `design: draft`"); AC2; `land.spec.luau:142-184`
Evidence:
- The capture's stub is published by `new` with `design: draft`, so its `origin/main` copy is always draft. A capture that edits its own document to `design: ready` and `status: prepared-x-y-z`, then runs `land`, passes every scope rule. That is one `M` of a backlog `<ID>.md` whose origin copy is draft.
- It is then on `main` as a ready, prepared issue, with the stub's placeholder `check.sh`, so `tracker.sh ready`/`start` accept it with no design review and no real acceptance checks.
- The same applies to any other draft issue a capture touches. The tracker skill says that only `ticket-prep` sets `design:`, and that the only way to change tracker state (the `status:` line) is `tracker.sh`. Land is the one path to `main` that enforces neither.
- No spec case edits the `design:` or `status:` line of a draft document, so a correct implementation of the current Design and a stricter one both pass.
Critique: the tempting fix is to also read `HEAD`'s copy for `design: draft`. That closes `design:` but still lets a capture rewrite `status:`, the state that `ready` checks (`statusLib.canMove(st, "active")` needs `prepared`).
Consequences:
- The rule now compares two copies. For an `M`, both copies must say `design: draft`, and the `status:` line must be byte-identical to `origin/main`'s. For an `A` there is no origin copy (see F2), so the added document itself must say `design: draft`, with no `status:` other than a `new-…` stamp.
- make-issue never changes either line, so legitimate captures are unaffected.
- The refusal must name the path and the field.
Recommendation:
- Add to step 3: "both copies say `design: draft`, and the `status:` line is unchanged from `origin/main`'s".
- Add two sub-cases to "land refuses anything but…": the capture's own document edited to `design: ready`, and its `status:` line edited. Each names the path and pushes nothing.
- Add a Rules row whose mutant is "reads only `origin/main`'s copy".
- Mirror the rule in the tracker skill's direct-push exception wording ("a draft issue's document, never its `design:` or `status:` line").

### F2 [medium] The two `A` rules (a new `<ID>.md`, a new `check.sh`) have no spec case either way, and an added document may reuse an id that already exists elsewhere on `origin/main`
Where: c0072 Design step 3 (first two bullets); AC2 ("an added or edited draft backlog `<ID>.md` or an added `check.sh`"); `land.spec.luau`
Evidence:
- In every case of the spec, the capture's issue was created by `new` with publishing on (`scripts/tracker/main.luau:355-391` publishes both `<ID>.md` and `check.sh`). So every allowed line the spec lands is an `M`.
- A mutant that refuses every `A`, or every `check.sh`, passes AC1–AC4.
- The `A` path is reachable. When `new` can't publish, it says to run with `PICKMAN_PUBLISH=0`, which creates the stub locally, and a later `land` pushes it as two `A` lines.
- Nothing checks that the added id is free. An `A` of `tracker/issues/c0073/c0073.md`, while c0073 sits in `active/` or `done/` on `origin/main`, is a backlog path of the right shape, so land pushes a duplicate id to `main`. The tracker skill treats a duplicate as a conflict to renumber, and `store` resolves ids by directory scan.
Critique: the tempting fix is a positive case only. That leaves the duplicate-id hole.
Consequences: a uniqueness check reads `origin/main`'s tree for the id in any state directory. That is cheap: one `git ls-tree -r --name-only origin/main -- tracker/issues`. Land then refuses and names `tracker.sh renumber`, as the skill's Conflicts rule already does.
Recommendation:
- Add a case "land lands an issue created without publishing": `PICKMAN_PUBLISH=0 tracker.sh new issue …` in a capture worktree, then `land` with publishing on. Assert that the pushed diff is exactly `A <ID>.md` and `A check.sh`.
- Add a refusal sub-case for an `A` of `<ID>.md` whose id exists under `done/` on `origin/main`.
- Add Rules rows (mutants: "refuse every `A`" and "no id check").
- Alternatively, drop the `A` rules and refuse them, saying so in AC2 and in make-issue ("a capture created without publishing lands by PR"). Either way, the spec must pin the choice.

### F3 [low] An add into `done/` that carries a status line both starts and ends a spell in one commit; the order is unspecified and unasserted
Where: c0073 Design `history.parse` (the first bullet and the close-day bullet); `history.spec.luau:65-66,141-144`
Evidence: the fixture's c0004 is added straight into `done/` with `status: active-m-n-o`. The first rule starts an `active` spell, and the close rule ends "the open spell", both at 2026-10-02T23:00.
- If the status line is handled first, the result is a zero-length spell with both ends known. That spell is counted (n=1, mean 0), which pulls medians down.
- If the close is handled first, the spell is left open and isn't counted.
The spec asserts only `closed.c0004`. On today's data no add into `done/` changes or introduces a status (all 7 are unchanged moves), so the effect is future-only: emergent issues that carry a status stamp.
Recommendation: state that "an add or move into `done/` never starts a spell; it only ends the open one". Add `stats.durations` over c0004's parsed spells to the close-day case, asserting `active.all.n == 0`, and add a Rules row (mutant: status handled before close).

### F4 [low] Three edges of c0073's definitions are left to the implementer
Where: c0073 Design "Views: quarter", "Today", and the `Stats` type
Evidence:
- **Quarter clamping.** "The Monday on or before (today − 3 months)" doesn't say how to clamp. Only the month view says "clamped". For 2026-05-31, clamping gives 02-28 → Monday 02-23, while overflow gives 03-03 → Monday 03-02. No case pins either.
- **History without item commits.** "With history, the day of the last commit…" doesn't cover a repository whose log under `LOG_ARGS` is empty (`parse(...).today == nil`), such as a fresh fixture clone before any item exists. Does it fall back to the data, or give `""`?
- **The `periods` type.** With `today == ""`, `periods` is "an empty table", but `Stats.periods` is typed `{ week: Row, month: Row, quarter: Row, year: Row }`. Under `--!strict`, `{}` doesn't type-check against it, so the implementer has to cast or deviate.
Recommendation:
- Say "the same clamp as the month view" for the quarter.
- Define today as "history's last-commit day when there is one, otherwise the latest date in the data, otherwise `""`".
- Type `periods` as `{ week: Row?, … }` or `{ [string]: Row }`.
None of these needs a new spec case, but a quarter case for 2026-05-31 would pin the first.

Verdict: changes
