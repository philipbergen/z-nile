# Refute 007: R0042
Round 007 is this re-prep's round 2. One question went to the user on 2026-10-20: may c0119 add a read-only helper, since a git recipe in skill prose can't find an item's capture reliably? The user had declined a `tracker.sh scope` command earlier. The answer was "Yes: `tracker.sh capture <id>`".

Verification on `.worktree/proto-scope-fidelity`, synced with this tree:
- `scripts/check.sh --full` printed `GATE PASSED (full)`. The first run failed `tests/acceptance/c0044/guard` on two new specs that spelled legacy `<ID>-<slug>.md` names. Both now build those names by interpolation (harvest note).
- c0111's `check.sh` passed 11/11, and c0119's passed 4/4.
- `promote-check R0042` printed `promote-check OK`.
- `luau-lsp analyze` of both acceptance folders and `scripts` exited 0.
- `lessons --check` printed `21 lessons, 91 harvest entries, ok`, and `--uncovered R0040 R0042` printed that every finding is covered.

- F1: fixed. The lookup is now code, not a recipe.
  - c0111 adds `scripts/tracker/trail.luau`, which reads an item's backlog, `active/` and `done/` folders, and, before the last compaction, the id `tracker/compaction.txt` renamed. An id that compaction renamed away has no pre-cut history; an id the map doesn't mention keeps its own. It uses `--no-renames`, never `--follow`, and a legacy slug-named document counts. `trail.capture` takes the newest `tracker: new <f|d|c>NNNN` commit, or else the first add.
  - c0119 adds `tracker.sh capture <id>` (read-only, reads `origin/main`), and ticket-prep, item 11, 5.5 and ready-raft name it. The tracker skill lists it in its command table and in the main-checkout list.
  - The audit list was rebuilt with the prototype's `capture` over every member of the five prepared rafts. All ten differ from their captures, including f0027 (first add `a985927`, slug-named) and c0083 (`cda52f9`, as c0890, before compaction). R0042's Risks lists them, and the next `compact` keeps working because the map names the old ids.
  - Evidence: `capture` on the real tree printed `cda52f9 tracker/issues/c0890/c0890.md tracker: new c0890 …` for c0083, and `a985927 tracker/issues/f0260/f0260-touch-turn-controls.md …` for f0027.
  - consequences: c0119 now has code (`main.luau`, AC4, `capture-cli.spec`, 6 cases), and c0111 has AC10 (`trail.spec`, 4 cases). Their rows ran: the 19 mutants of the trail, the command, the metrics reader and the new skill text each failed their case. `capture` stays out of `READ_ONLY`, which `tests/tooling/tracker-guarded` pins, so it checks the repository root.
- F2: fixed. The metrics reader uses `trail.oldestAdd` and no longer follows renames.
  - The fixture adds a raft whose first review is committed with `GIT_COMMITTER_DATE` 2020, deleted, written again to equal R0020's review byte for byte, and moved into `done/`. It counts as before: `| before | 1 | 2 | 2.0 |`.
  - The mutants "newest add" and "follow renames" fail it. With `--follow`, git took the re-added file as a copy (`C068`) of R0020's.
  - consequences: one git call per range per raft, two ranges at most.
- F3: fixed: c0111's nine captured Solution bullets are back verbatim, followed by an "As designed" paragraph that points to the `Scope decision` lines. ticket-prep's scope paragraph says to keep captured Solution bullets as they are and add after them, and it has an assertion and a row (mutant killed). consequences: the ready-raft scope step will stop on the ten listed members until the user confirms each one, which is the audit the user chose.
- F4: fixed:
  - c0119's Design, Usability and lesson bullet now use `tracker.sh capture` and "acceptance criterion".
  - R0042's diagram reads "capture (`tracker.sh capture <id>`)".
  - Item 11's high clause and the lesson's check accept `Scope decision` or `Decided with the user` lines. That clause has an assertion and a row (mutant killed).
  consequences: none.
