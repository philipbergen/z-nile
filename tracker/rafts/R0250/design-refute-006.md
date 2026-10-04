# Refute 006: R0250 design review 006 (c0780, c0790 added)

- F1: fixed: board-stats calls `board.collect(tree .. "/tracker")`. The design keeps `collect`'s tracker-directory contract and reads history from its parent (`history.read(<root>/..)`; the default `"tracker"` gives `"."`). Rules row added.
- F2: fixed: the expected count is 32 (2025-05-12 through 2025-06-12), consistent with `stats.spec`'s 32 for 2026-03-31.
- F3: fixed: the case takes `before` after `capture("capture-e")` has published its stub.
- F4: fixed: the scope is `--name-status --no-renames`, and only these pass: `A`/`M` of exactly `tracker/issues/<ID>/<ID>.md` in the backlog (an `M` only while origin's copy is `design: draft`) and `A` of `tracker/issues/<ID>/check.sh`. A new case refuses a deletion, an `acceptance/` file, a `done/` item, an edited `check.sh` and an edited `design: ready` document; each names the path and pushes nothing. Rules rows were added for the prefix and `--name-only` mutants.
- F5: fixed: AC5 greps the `**The direct-push exception.**` line itself for `tracker.sh land`. The Regression guard says to keep that exception on one line, and to keep `tracker-only` (RC7).
- F6: fixed: the close day is the first commit adding a document of the item (`<ID>.md` or a legacy `<ID>-<slug>.md`) under `tracker/issues/done/<ID>/`, whatever was deleted with it, and later adds don't move it. history.spec gained an emergent add straight into `done/` and a slug-named document renamed inside `done/`. The real-tracker case now also requires `closed > 0` over the year.
- F7: fixed: with no dated data, today is `""`, the views are empty, and the page says `no dated data`. Issues without `created:` are left out of "opened". A new board-stats case covers an undated tree.
- F8: fixed: history.spec gained c0030, readied, stopped, readied again and finished, with each move changing the status. It asserts prepared n=2 (0.5 and 0.5 days) and active n=2 (0.5 and 1.0, mean 0.75), plus a Rules row.
- F9: fixed: `LOG_ARGS` is limited to item documents with glob pathspecs (`[fdc]NNNN*.md`, `RNNNN*.md`, legacy names included). Remeasured: 4.1 MB in 0.06 s. The budget is under 0.5 s at ten times today's history, with a cache keyed by the `HEAD` sha as the fallback.
- F10: fixed: there is one definition of today: the day of the last tracker-document commit on `HEAD`, otherwise the latest date in the data, otherwise `""`.
- F11: fixed:
  - land prints `gate: <command>` and says `(gate overridden)` when the variable is set; the first case asserts it;
  - a failed push is retried only if `origin/main` moved; otherwise land fails with git's output;
  - the Test plan now describes the gate-script race and notes the script as a reviewed exception to the fixture rule;
  - `guardRepoRoot()` runs in step 1.
- F12: fixed: c0790's Regression guard keeps `tracker.sh board`, `.cache/board.html` and `--open` (c0400 AC5), and c0780's keeps `tracker-only` (RC7).
