# Refute 006: c0120 (code review 006, changes; the coordinator's round 003 of #107)

New commits on `impl2-c0120` and prep commits merged in; the earlier groups untouched.

- F1 (high), in prep: AC18 stops hand-coding events and reads each item's files where the tracker puts them.
  - Promotion: a reference `acceptance/<rest>` missing from its item's folder is looked up at `projects.promotedDir(reg, <root now>, <id>)/<rest>`, a new engine function that `done` itself now uses (the one reader of that place). There it is judged against its text before the move; c0114's against that text with `c0114-overrides.patch` applied (`git apply` in a scratch folder under `z-nile/.cache`, outside every repository). In neither place: `deleted`.
  - A `check.sh` finished after the move's base: its expected text is `rewrites.rewrite(paths.rewrite(old, {[id] = <its done folder>}), home, world)`, the done folder in either root (finished on main before the merge, or after).
  - The rewrite's folder map (`rewrites.world`'s `moved`) is pinned to the move commit's own renames, not HEAD's: a later merge that finishes an item no longer shifts where a folder went (it made R0010's finished `check.sh` red in the simulation). A rerun of `rewrite-finished.luau` on the branch changes nothing.
  - A compaction merged in (an id renumbered in `z-nile/compaction.txt` since the move) refuses, naming the renumber.
  - override-markers bases a newly promoted spec (status A under a `tests/acceptance`) on its item text before the move (a blob diff), so only c0120's own edits need markers.
  - `c0114-overrides.patch` is regenerated with a marker at every hunk (28 added, by the same rule as group 3's), so c0114's promoted specs pass override-markers.
  - finished.spec's fixture runs `done`'s steps with the engine's own functions (`projects.promotedDir`, `git mv`, `paths.rewrite`): f0065 done → green; its promoted spec edited → changed; removed → deleted; c0114 done with its patch → green, one hunk beyond → changed; a duplicate folder → refused; a compaction → refused. The old cases are kept.
  - Mutants: V17 (promotion read as deletion again), V18 (the patch ignored), V19 (duplicates not seen), V20 (compaction not refused): killed.
  - Merge simulation, in a scratch clone: today's origin/main's R0034 and f0065 done at their new places (main's own files, `acceptance/` promoted), `rewrite-finished` rerun, then c0114's `done` with the tool and the patch; with an approving stub review pinning the simulated prep: AC18 green (221 files), override-markers all 1088 hunks marked.
- F2: repo-fence's "one owner" case scans every tracked `.sh` and `.luau` file (fence.sh, item and promoted specs, specs and cachepaths' quoted list aside) and fails any `pickman_*fence*` call but `pickman_fence_all`, `pickman_fence_dirs` and `pickman_guarded`, allowing the runner's jailed-shell line exactly. V21 (a `pickman_home_fence` planted in `pickman/check.sh`) killed.
- F3: AC18 refuses a key listed twice (a duplicate item folder), at HEAD or before the move, naming both paths. V19 killed.
- F4: `pickman_fence_dirs` refuses when `projects.toml` exists but `z-nile/roots.luau` doesn't; it falls back only without the registry. fence-every-home has the case; V22 killed.
- F5: homes.spec's broken-registry case requires `projects.toml's homes; refusing` or `is under no project root`.
- Lessons: review/sequestration-reference-not-a-ref (model each event through the tracker's reader; pin to the move commit), tracker/item-history-spans-moves-and-compaction (a compaction refuses); the reviewers' note (a Recommendation about an event names all its effects) is on review/sequestration-reference-not-a-ref. harvest.md has the entries.
