# Review 006: R0025 (design mode)
Inputs: prep-ready-raft at 57f1340 (c0072, c0073: documents, check.sh, acceptance specs; R0025.md, its check.sh; the c0067/c0070/c0062 designs for fit), R0021 at origin/R0021-check-isolation a7922db (fixture.luau, fence.luau, repo-fence.spec NAMES, c0060 retrofit scan). Spot checks: the stats spec's numbers worked by hand; a scratch repository built with the history spec's commits and run with `LOG_ARGS`; `git log` sizes and timings on this repository; luau-lsp strict analysis of all four new specs in a scratch clone of R0021 with stub `stats`/`history` modules typed per the Design. Only the expected `Model.stats` errors came back.

Verified and fine: every expected number in `stats.spec.luau` (floor, the 31/32/14/13 bucket counts, periods, week/Sunday/Monday rows, the four ratios with their one-decimal rounding as exact doubles, durations including the +02:00 offset, the year[12]/year[13] counts). `history.spec` matches git's real `--no-renames -p --unified=0` output: a move prints the add before the delete (sorted paths), deleted frontmatter lines print as `----`, and `%cI` carries the zone. Both `check.sh` files work in bash 3.2 (`AC_LIST=1` lists 5 and 7 criteria; `\b` works in BSD and GNU grep). Every case prefix exists in its spec. Post-promotion fallbacks are right. No banned name or non-`example.invalid` identity in either issue. The fixture directories are unique.

### F1 [high] board-stats passes the parent of `tracker/` to `board.collect`, whose root is the tracker directory, so a correct implementation finds no items
Where: `tracker/issues/c0073/acceptance/board-stats.spec.luau:14,37-47,78`; `scripts/tracker/board.luau:147-149` (`local base = root or store.ROOT`, then `scan(base, "issues")`); c0073 Design "Board"
Evidence: the spec writes `{tree}/tracker/issues/f0010/f0010.md` and calls `board.collect(tree)` with `tree = .cache/c0073-board`. `collect` scans `{root}/issues` and `{root}/rafts`, and `store.ROOT = "tracker"`, so it reads `.cache/c0073-board/issues`, which doesn't exist. The model is empty, so there is no `today = "2025-06-12"` and no rows. c0042's promoted specs pin the tracker-directory contract: `model.spec` passes `.cache/c0042-model/tracker`, `page.spec` passes `.cache/c0042-page-a/tracker`, and `smoke.spec` passes `{DIR}/tracker`. So an implementation can't change the contract to fit this spec without breaking those three. The Design also never says how `collect(root)` finds the repository that `history.read` needs: it is the tracker directory's parent, which is `.` for the default `"tracker"`.
Critique: the tempting fix is to make `collect` accept either form ("use `{root}/tracker` when it exists"). That adds a hidden rule that c0042's fixtures could trip.
Consequences: the history root has to be defined. If it is the parent of the tracker directory, c0042's page B (`.cache/c0042-page-b/somewhere/else/tracker`) gets parent `…/else`, which is not a repository top, so it has no history, and `htmlB == htmlA` still holds.
Recommendation: change the spec to `board.collect(tree .. "/tracker")` in both places. State in the Design that `board.collect(root)` takes the tracker directory, as today, and calls `history.read(<root>/..)`; the default `"tracker"` gives `"."`. Add a Rules row, "history is read from the tracker directory's parent", backed by the board-stats case: a `collect(tree)` mutant would find no items and fail on `today`.

### F2 [high] board-stats expects 31 month buckets for a today of 2025-06-12; the Design's definition gives 32
Where: `board-stats.spec.luau:51-52`; c0073 Design "Views: month"; `stats.spec.luau:73,79` (consistent with the definition)
Evidence: month = "from the same day one month back … through today", one bucket per day, inclusive of today. `stats.spec` uses exactly this: 2026-10-03 gives 09-03…10-03, which is 31 buckets because September has 30 days, and 2026-03-31 gives 02-28…03-31, which is 32. For 2025-06-12 the window is 2025-05-12…2025-06-12: 20 days in May plus 12 in June, so 32. `t.expect(#s.views.month).toBe(31)` fails for every implementation that passes `stats.spec`.
Critique: the tempting fix is to cap the month view at 31. That breaks `stats.spec`'s clamped case (32) and changes the user-facing definition.
Consequences: none beyond the one number.
Recommendation: change the expectation to `32`, with a comment ("2025-05-12 … 2025-06-12: May has 31 days"). Or move the fixture dates so that the previous month has 30 days, for example June to July, and keep 31.

### F3 [high] land's "refuses outside…" case reads the origin tip before `capture("capture-e")` publishes a stub, so its final `tip() == before` fails for a correct `land`
Where: `tracker/issues/c0072/acceptance/land.spec.luau:151,157,166`
Evidence: `local before = tip()` is line 151. Line 157 calls `capture("capture-e", "epsilon")`, which runs `tracker.sh new issue c epsilon --desc …`. In this fixture that command publishes the stub to `origin/main` (publishing is on: there is an origin and no `PICKMAN_PUBLISH`, and the first case's comment relies on this: "the stub is already on origin (new issue published it)"). So origin's `main` moves after `before` is read, and line 166 fails even when every refusal is correct. AC4 can't pass.
Critique: the tempting fix is to drop the final assertion. Then a `land` that pushes on a dirty tree would pass.
Consequences: none.
Recommendation: read `before` after the `capture("capture-e", …)` and `worktree capture-f` setup, and assert `tip()` is unchanged after each refusal: after `named`, after `dirty`, and after `nothing`. The dirty case also needs an untracked-only mutant to be killed. `stray.txt` is untracked, so a cleanliness check with `git diff --quiet` would let land push. The per-refusal tip assertion catches that.

### F4 [high] c0072's scope check can be passed by a prefix check, and its rule lets a capture push deletions and edits to sequestered `check.sh` files to `main` with no review
Where: c0072 Design step 3; AC2; `land.spec.luau:129-139` (the only scope case uses `scripts/extra.txt`)
Evidence:
1. The spec's one negative case is a file under `scripts/`. A mutant that only checks for the prefix `tracker/` (or `tracker/issues/`) passes AC2. So would pushing `tracker/issues/<id>/acceptance/x.spec.luau`, `tracker/issues/done/<id>/<id>.md` or `tracker/rafts/…`.
2. The rule uses `git diff --name-only`, which lists deleted paths too. A capture that deletes `tracker/issues/c0123/c0123.md` matches "`<ID>.md` of an issue in the backlog" and would be pushed to `main`.
3. The rule allows any backlog `check.sh`, including that of a `prepared` (`design: ready`) issue. Those files are sequestered: ticket-prep writes them and they are reviewed. The tracker skill's existing direct-push rule allows "a `check.sh` only when it is created". `land` would widen that to "any edit, after a local gate", for a path that execution may not change.
Critique: the tempting fix is a regex on the path alone. That still misses deletions and edits to prepared items.
Consequences: refusing edits to prepared items means a note on a prepared issue goes through a PR, so the make-issue skill must say so. Also, the diff must come from the merged tree against `origin/main`. It already does, so a file that someone else deleted on `origin/main` isn't counted against the capture.
Recommendation: specify the scope as `git diff --name-status --no-renames origin/main HEAD`, refusing:
- any status other than `A`/`M`;
- any path other than `tracker/issues/<ID>/<ID>.md` or `tracker/issues/<ID>/check.sh` (exact shape, backlog directory);
- `check.sh` with status `M`;
- an `M` to a document whose `origin/main` copy has `design:` other than `draft`.

Add spec cases (all assert nothing pushed and that the path is named): a deleted issue document; an `acceptance/` file in the backlog issue; a `done/` issue document; an edit to an existing `check.sh`. Add Rules rows for each, with the prefix-check and `--name-only` mutants. Mirror the rule in the tracker skill's direct-push exception.

### F5 [high] c0072 AC5's direct-push-exception check already passes on today's skill text
Where: `tracker/issues/c0072/check.sh` AC5, `grep -i "direct-push exception" -A3 "$t" | grep -qF "land"`
Evidence: `.claude/skills/tracker/SKILL.md:140` reads "**The direct-push exception.** Everything else lands by pull request." "lands" contains "land", so this sub-check is green with no change at all. A skill edit that never mentions `tracker.sh land` in the exception passes AC5.
Critique: the tempting fix is `grep -w land`. That still matches prose such as "land by PR".
Consequences: none.
Recommendation: match the command, scoped to the bullet: `grep -F "**The direct-push exception.**" "$t" | grep -qF "tracker.sh land"`. Keep the rest of AC5. If c0072's own wording puts `land` in a following sentence, keep the exception on one line, as the skill already does.

### F6 [high] The close-day rule misses about a third of the real done issues, so "closed" and the ratios are wrong on the real board
Where: c0073 Design `history.parse` ("into `done/` ends the open spell and gives the close day", defined for a *move* of `<ID>.md`)
Evidence: on this repository, a commit that both deletes `tracker/issues/{,active/}<ID>/<ID>.md` and adds `tracker/issues/done/<ID>/<ID>.md` exists for only 34 of 50 done issues. The other 16 fall into two groups:
- **Legacy slug-named documents**: c0001's R0001 commit 94c053a moves `c0001-ci-and-host-bootstrap-proven.md` into `done/`. The later migrate commit b76c5b0 deletes and adds within `done/c0001/`. That is not a move between directories, so there is no close. A looser parser would instead date the close to the migration.
- **Items added straight into `done/`**: emergent issues, created in `active/` on the raft branch, reach `main` by squash as a pure add.

The specs can't see this: `history.spec` only has `<ID>.md` moves, and the real-tracker case only checks `history == true` and `opened > 0`.
Critique: the tempting fix is to special-case the migration commit. Emergent issues would still be missed.
Consequences: closing becomes "the item's directory first appears under `done/`". A document must be recognised by id prefix (`<ID>.md` or a legacy `<ID>-*.md`). Re-adds within `done/`, such as a migration, must not move the day: the first add wins. The same event ends the open spell.
Recommendation: define close day = the first commit that adds a document of the item (`<ID>.md` or `<ID>-<slug>.md`) under `tracker/issues/done/<ID>/`, whatever was deleted. Add history cases:
- an emergent issue added directly into `done/` gets a close day;
- a slug-named document moved into `done/` and later renamed to `<ID>.md` within `done/` keeps the first day.

Add Rules rows, with the "move only" and "last add wins" mutants. Optionally strengthen the real-tracker case so that the summed `closed.all` over the year view is at least the number of `done/` issues closed inside it. That last one is judgement; a lower bound such as `> 0` is enough.

### F7 [medium] "Today" is undefined when there is no history and no dated data, which is exactly c0042's fixtures and the tooling spec's empty tree
Where: c0073 Design "Today" ("otherwise the latest date in the data (`created:`, spend rows)"); `tests/acceptance/c0042/{page,model,smoke}.spec.luau` (no `created:` and no `spend.md` anywhere: `grep -c created` gives 0); `tests/tooling/board.spec.luau:69` (an empty tree)
Evidence: these trees have no repository of their own, so no history, and no dates. `stats.compute(items, spends, today, …)` and `stats.buckets(view, today)` need a `today`, and the Design gives none. An implementation that errors breaks four promoted c0042 specs and a tooling spec. One that falls back to `os.date` breaks the "never the wall clock" rule and the c0042 byte-equality (`htmlB == htmlA`) across midnight. Also undefined: an issue without a parseable `created:` (`Item.opened: string` is required).
Critique: the tempting fix is to pick a fixed epoch day. That renders a misleading 1970 window.
Consequences: the page must render an empty Stats section without errors, so the guards in the script cover empty views. The encoder writes empty lists as `[]` (page.spec's "never `{}`" rule), so the script can iterate them safely.
Recommendation: specify that when no `today` can be derived, `stats` is `{ today = "", history = <bool>, views = { month = {}, quarter = {}, year = {} }, periods = nil-free empty rows or omitted, durations = {} }`, and the page shows "no dated data". Issues without a valid `created:` are left out of "opened". Add a board-stats case: a tree with undated issues collects without error and has `today == ""` and empty views. Add a Rules row with the `os.date` fallback as the mutant.

### F8 [medium] No spec case covers a move whose status changes (ready, stop), which is the new main lifecycle
Where: c0073 Design `history.parse` ("A move whose status value changed (`ready`, `stop`) starts a spell of the new status"); Rules and mutants (no row); `history.spec.luau` (moves only with unchanged status)
Evidence: after c0067, every readied raft's issues move `backlog → active/` with `prepared → active-…`, and `stop` moves them back with `prepared-…`. The fixture has neither. Two mutants pass the spec:
- "a move into `active/` always starts `active`, and a move out is ignored": a stopped issue keeps an open `active` spell, then later a second one;
- "a move's re-added status line is ignored": the `stop` back to `prepared` never starts a spell.
Critique: the tempting fix is to add only a ready case. `stop` is the one the mutants miss.
Consequences: none beyond the cases.
Recommendation: extend the fixture with an issue that is readied (moved to `active/` with `prepared-…` changed to `active-…`), stopped (moved back with `prepared-…`), readied again, and moved to `done/`. Assert its `prepared` and `active` spells (n=2 each, with hand-worked durations) and its close day. Add the Rules row.

### F9 [medium] `LOG_ARGS` reads 10 MB of patches for 108 commits on every board build; E1 measured a different, filtered command
Where: c0073 Design `history.LOG_ARGS`, Scalability, E1
Evidence: E1 timed `… -G'^status: ' …` (0.44 MB here). `LOG_ARGS` has no `-G`, so it prints every patch under `tracker/issues` and `tracker/rafts`: designs, reviews, acceptance specs, spend. On this repository that is 10,332,200 bytes, and git plus a Lune line scan takes about 0.35 s, growing linearly with history. c0070 runs a board build after every publish and every main-checkout `sync`, and several promoted specs build the real board. Restricting the pathspec to item documents, `':(glob)tracker/issues/**/[fdc][0-9][0-9][0-9][0-9]*.md' ':(glob)tracker/rafts/**/R[0-9][0-9][0-9][0-9]*.md'`, gives 2.7 MB in 0.10 s. It keeps whole-document adds and deletes, so moves are still seen, and it also matches legacy `<ID>-slug.md` names (F6).
Critique: the tempting fix is `-G'^status: '`. With pickaxe, a status-less legacy document's move is dropped, which loses those close days (F6).
Consequences: the history spec runs `fixture.git(repo, history.LOG_ARGS)` unchanged, because its paths match the globs.
Recommendation: set `LOG_ARGS` to the glob pathspecs above, and record a new E1 with the exact `LOG_ARGS` (bytes and seconds, including the parse). State a budget in Scalability, for example under 0.5 s at ten times today's history, with the fallback of caching the parse by `HEAD` sha under `.cache/`.

### F10 [low] "Today" is defined three ways
Where: c0073 Design: "Today: the date of the commit `HEAD` points at"; `history.parse` "`today` is the last commit's day" (of a log restricted to tracker paths); Solution "reads … from `git log` of `main`" (but `LOG_ARGS` names no ref, so it is `HEAD`)
Evidence: after a code-only commit, `HEAD`'s day and the last tracker commit's day differ. The spec fixes only the second meaning (`parsed.today`).
Recommendation: define today as `history.parse`'s last-commit day (the last commit touching the tracker), say the log is of `HEAD`, and fix the two sentences.

### F11 [low] c0072 loose ends: the gate seam is silent, any push failure is retried with a full gate, and the Test plan and spec disagree on the race
Where: c0072 Design steps 4 and 5; Test plan ("made by a pre-push hook"); `land.spec.luau:169-188`
Evidence:
- `PICKMAN_LAND_GATE=true` lands with no gate and prints nothing that says so.
- "On a rejected push, go back to step 2" doesn't separate a non-fast-forward from an auth or network failure, so a bad remote costs three full gates of about 50 s each.
- The Test plan names a pre-push hook, but the spec races from the gate.
- The racing gate script runs raw `git pull/commit/push` in `other`. It is guarded by `cd … || exit 1` and lives under `.cache`, but it is outside the raft's "raw git only for rev-parse and init/clone" rule.
- The Design doesn't say that `land` calls `guardRepoRoot()`, as every repository-changing command does.

Recommendation:
- Print `gate: <command>` before running the gate, and add "(gate overridden)" to the `landed` line when the variable is set.
- After a failed push, `git fetch origin main`, and retry only if `origin/main` moved; otherwise fail with git's output.
- Fix the Test plan wording, and note the gate script as a reviewed exception to the fixture rule.
- Call `guardRepoRoot()` in step 1.

### F12 [low] Regression guards omit promoted tokens in the tracker skill that both issues' edits must keep
Where: c0072 and c0073 Regression guard
Evidence:
- c0073 rewrites the board row. c0042's done `check.sh` AC5 needs `tracker.sh board`, `.cache/board.html` and `--open` in the tracker skill. The row is where the last two live, and c0070's token list doesn't name them.
- c0072 edits "The direct-push exception". RC7 (c0053 AC6) needs `tracker-only` or `paths-ignore` in the skill, and that bullet is where `tracker-only` lives.

Recommendation: list these tokens in each issue's Regression guard.

Verdict: changes
