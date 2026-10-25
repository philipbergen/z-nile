# Review 006: c0120 (code mode; the coordinator's round 003 of #107)
Inputs: `origin/impl2-c0120` at 9c884e7e (PR #107). Fix delta `git log --first-parent 61488eb7..9c884e7e`: d75c5e3, 1b835f0, f1592c2, a0eca45, d10faf3, 55dddec, bf85f5e, a0d00f5, 48cff53, 4bb7c28, a700819, 40d4e1d, ca77879, fae7634, 9c884e7, plus the prep commits merged in (`origin/prep-c0120` adbb1188..3888c8e3: 00fb46f, 223f8c1, 7d27f13, 3888c8e). Read first: review-005, refute-005, c0120.md (Implementation steps, JC1, Overrides), `./zn lessons --when build --full`, `./zn lessons --skill review --full`. Every run was in scratch clones under this folder. Nothing was run in the real repository or its `.worktree/*`.
Dropped from review-005: F2, F3, F4, F5, F6 and F7. Each is answered as refute-005 says, and the checks are below. F1's fix holds for what it tests, but it opens a new hole in the same mechanism (F1 here). That hole comes partly from review-005's own Recommendation (c), which modelled "finished by a later merge" as a folder move and never as `done`'s promotion.
The user's decisions applied: "Reviewer-pinned commit" (AC18) and "Reviewed by commit group" (the earlier groups are untouched; the new commits are judged as one group of their own).

## What was run
- **Gates**, each in its own clone at 9c884e7e:
  - `z-nile/check.sh --full`: GATE PASSED. pickman 1162/173, z-nile 844/122, 186.9 s.
  - `pickman/check.sh --full`: GATE PASSED. 1162/173.
  - `z-nile/scripts/check.sh --full`: GATE PASSED. 844/122, 183.8 s.
- **c0120's `check.sh`** (`./zn check c0120`): 15/18, and each red is red for its stated reason.
  - AC11: only `z-nile/.tracker/issues/c0114/check.sh: tracker/next` and `z-nile/next (from z-nile)`.
  - AC16: only `busy: cannot read origin/main`.
  - AC18: `no approved review … records a "Prep reference: <sha>"`.
- **AC18 with an approving review in place.** I put a stub `review-006.md` (`Prep reference: 3888c8e3…`, `Verdict: approve`) in clone `ac18` and got `221 sequestered files are their text before the move … as review-006.md records them`, which is green. The new walk, attacked in the same clone:
  - `git rm` of c0120's `acceptance/runner-home.spec.luau` → red, `deleted`.
  - `git rm` of f0065's `check.sh` → red, `deleted`.
  - A new `acceptance/x.spec.luau` in c0120's folder → red, `added`.
  - Two `Prep reference:` lines → refuses.
  - `Verdict: approve` followed by a later `Verdict: changes` → not read; refuses.
  - A newer `review-007.md` with `Verdict: changes`, with or without a reference → the approving review-006 is still used. That's right: AC18 judges sequestration, not approval.
  - **A state change through a merge**: red. See F1.
  - A duplicate item folder: green. See F3.
- **`override-markers.luau -- f83441d6`**: `all 970 hunks are marked (within 3 lines)`. The F6 commits (d10faf3, 55dddec, bf85f5e, a0d00f5) change only comment lines, plus stylua's reflow of the `t.expect(` calls whose markers moved out of them.
- **Promotion dry run.** I copied c0120's acceptance folder into `z-nile/tests/acceptance/c0120/` and ran `z-nile/check.sh --full`. Every static stage passed (luau-lsp 0 errors, 0 parse errors). Tests: pickman 1162/173, z-nile 947/136, with 1 failure: check-paths' live case (AC11's expected red, c0114's two paths).
- **Mutant spot-run.** V12 (`ac.sh` back to `pickman_home_fence "$(pwd -P)"` alone) turns fence-every-home red: 3 of 4 cases fail. Killed.
- **Repository safety (item 8).** Clone `mac` is macOS as shipped (jailed). Clone `lin` has `jail()` patched to the non-macOS branch. I took a fingerprint (refs, index, config, worktrees, HEAD, hooks) before and after every batch, and it never changed. The exception is one change in `lin` on the first run after my patch of `fence.luau`: git's stat refresh of the index. `ls-files -s`, refs and config were identical, and later runs were stable. Results:
  - **`check.sh` probes into every home's `.cache`.** A fixture `check.sh` sourced `z-nile/lib/ac.sh` by path, so an inherited `GIT_DIR` can't stop it before the fence. Matrix: a pickman item and a z-nile item, run from the root, `pickman/` and `z-nile/`, with no sentinel in any `.cache`. Inherited environments: none, `GIT_DIR` (absolute, relative `.git`, with `GIT_WORK_TREE`), `GIT_COMMON_DIR`, a ceiling at the root, and a ceiling at root:pickman:z-nile. In every case, in `.cache` and in `.cache/atk` of the root, `pickman/` and `z-nile/`, git found no repository: `rev-parse`, `add -f -N`, `update-ref` and `commit` all failed. `update-ref` from the home was refused by the hook. **42 runs, 0 open.** `check.sh` files run unjailed on both OSes, so `lin` is the same code path.
  - **Bad `.cache` for a `check.sh`.** A symlinked `.cache`, an unwritable `.cache` (555, no sentinel) and a folder at the sentinel, each at the root, `pickman/` and `z-nile/`, × both projects × three starting folders. **54 runs.** Every one refuses before any check, and nothing was written through a link.
  - **The runner, inherited environment.** A probe spec in each home, run from `pickman/` and `z-nile/`. Environments: none, `GIT_DIR` (the clone's, relative, foreign), `GIT_COMMON_DIR` (foreign, the clone's), a ceiling at the root, and a ceiling at root:home. **32 runs** (16 in `mac` under `sandbox-exec`, 16 in `lin` under `none (…)`), 0 open. Each run's ceiling names all three `.cache` folders.
  - **The runner, bad `.cache`.** The same three kinds × three places × two homes. **36 runs** (18 per clone), and every one refuses before any spec runs.
  - **The gate.** A symlinked `.cache` at the root, `pickman/` and `z-nile/`, under `--plan`, `--project pickman --plan` and `--project z-nile --plan`. **9 runs**, and every one refuses before any plan line. Review-005 F3 is closed.
  - **The fallback for a copy without a registry** (`pickman_fence_dirs` on synthetic trees):
    - No registry: the top plus the folders that hold a `.tracker/`.
    - A full registry and no `.tracker/` folders: every registry home.
    - A broken `projects.toml`: refuses.
    - `projects.toml` present but no `roots.luau`: falls back silently (F4).

### F1 [high] AC18 (and `override-markers.luau`, JC1's instrument) reads `done`'s promotion as a deletion; R0034 is already done on origin/main, so the next mandatory merge turns AC18 red, and c0114's done (AC11's precondition) does the same
Where:
- `z-nile/.tracker/issues/c0120/acceptance/finished.luau`, the reverse walk (`for key, b in base`, `deleted`);
- `finished.spec.luau`'s case "an item finished by a later merge moves to done/" (about line 290);
- `override-markers.luau`'s `git diff -U0 -M <renames> HEAD -- */tests/acceptance`.

Evidence:
- `done` `git mv`s an item's `acceptance/` folder to `<home>/tests/acceptance/<id>` (`z-nile/engine/main.luau`, cmd.done, "Promote sequestered acceptance specs"). Then it moves the folder to `done/` with its `check.sh` through `paths.rewrite`.
- On origin/main, R0034 is already done (b36d2643: `tracker/issues/done/f0065/`, `tests/acceptance/f0065/*.spec.luau`). Each of those files is byte-identical to its text at pre (aed3e6f1).
- Implementation step 12 requires a merge of origin/main before `done`. It moves such folders to the item's home.
- I simulated that resolution in clone `ac18` with the approving stub in place: f0065's `acceptance/` went to `pickman/tests/acceptance/f0065`, f0065 to `issues/done/`, and R0034 to `rafts/done/`. Result:
  - `finished: 7 of 214 sequestered files differ …`;
  - every f0065 spec is reported as `…/acceptance/<spec>: deleted (no acceptance/<spec> in f0065's folder now)`;
  - with that commit in place, `override-markers.luau -- f83441d6` reports `7 of 977 hunks have no "-- c0120 override:"`, because each newly promoted file is one unmarked added hunk.
- Simulating c0114's `done` the same way gives 14 `deleted` lines and `done/c0114/check.sh: not its text with exactly the rewrite`. The rewrite is the one step 12 says to apply. c0114 must be done for AC11 to go green, and c0120 `depends_on` it.

So on the stacked build, no tree can have AC11 and AC18 green together without rebuilding the branch. And with R0034 already on main, AC18 can't stay green past the next merge. Before 00fb46f the forward-only walk skipped these files, so this is a regression from the F1 fix. finished.spec's fixture moves f0065's folder to `done/` with its `acceptance/` inside it, which `done` never does, so the spec passes against behaviour that doesn't exist.

Critique: this is the third round to find a hole in AC18's reference and identity (review-004 F1: a branch ref; review-005 F1: presence; now promotion). Each fix teaches AC18 one more tracker lifecycle event by hand: state folders, then promotion, with compaction (renumbered ids) and `paths.rewrite` of a moved `check.sh` still to come. The tempting fix is "also look in `<home>/tests/acceptance/<id>`". That alone isn't enough:
- c0114's promoted specs then get c0120's own overrides (`c0114-overrides.patch`, Overrides list), so judging them against pre makes them red;
- override-markers would still flag every newly promoted file.

Consequences:
- A promoted file changes owner. It leaves sequestration, and the Overrides rule and the override markers govern it from then on. So AC18 and override-markers must agree on where the boundary falls: AC18 judges the file up to its promotion, and override-markers judges every edit after it.
- A finished `check.sh` that arrives through a merge has had both `paths.rewrite` (done's item paths) and step 12's `rewrites.rewrite` applied. Its expected text is the composition of the two, in that order. Today no unfinished `check.sh` names its own item path, so this part is latent.
- A compaction merged from main renames ids. Keyed by id, every file of the item reads as `deleted` plus a capture.

Recommendation (in prep, as Guess 18 allows for c0120's own files; the criterion's text already covers promoted files, so no scope change):
- (a) **Promoted files.** Read the promoted place through the same reader `done` uses (`projects.homeOf` / `acceptanceRoots`, lesson architecture/one-reader-per-format). For an item finished at HEAD, the pre file `acceptance/<rest>` is `promoted` when `<home>/tests/acceptance/<id>/<rest>` is tracked at HEAD. Judge it there against its pre text. For c0114, judge it against its pre text with `c0114-overrides.patch` applied (the design's Implementation step 9), or record that c0114's promoted specs are judged by override-markers alone. A file that is in neither place is `deleted`.
- (b) **Finished `check.sh`.** Expect `rewrites.rewrite(paths.rewrite(old, {[id] = <its done dir>}), home, world)` for an item that finished after pre.
- (c) **override-markers.** For a promoted folder that wasn't under `*/tests/acceptance` at the renames commit, take the base from its pre-move item path (`git show <pre>:<old acceptance path>`), so only c0120's own edits need markers.
- (d) **Compaction.** An id that the trail shows was renumbered after pre refuses with a message naming the renumber (lesson tracker/item-history-spans-moves-and-compaction). It never passes, and is never reported as `deleted`.

finished.spec cases, with a fixture item that has `acceptance/` and that a simulated `done` finishes (`git mv` of `acceptance/` to `<home>/tests/acceptance/<id>`, the folder to `done/`, its `check.sh` through `paths.rewrite`):
- that tree → green;
- the promoted spec edited → red, `changed`;
- the promoted spec removed → red, `deleted`;
- a c0114-like item with its overrides patch applied → green, and one hunk beyond the patch → red.

An override-markers case: the same simulated promotion → 0 unmarked. Mutants: the promoted place not consulted; the patch not applied.
Lesson: review/sequestration-reference-not-a-ref; tracker/item-history-spans-moves-and-compaction.

### F2 [low] repo-fence's "one owner" case hand-lists four files and three function names
Where: `z-nile/tests/tooling/repo-fence.spec.luau`, "every caller of the fence outside fence.sh takes its folders from pickman_fence_all".
Evidence (by reading): the case scans only `z-nile/check.sh`, `z-nile/lib/ac.sh`, `z-nile/tests/lib/fence.luau` and `z-nile/tests/run.luau`, and only for `pickman_fence_refusals`, `pickman_fence_sentinel` and `pickman_home_fence`. These would all pass:
- a `pickman_home_fence "$ZN_ROOT/x"` in `pickman/check.sh`, the engine or a new script;
- a `pickman_fence "$dir"` or `pickman_fence_ceiling "$dir"` on a hand-picked folder in one of the four.

Today every caller is fine: `git grep` finds only the four files plus `pickman_guarded` in `z-nile/engine/main.luau`. The lesson the refute extended ("grep every `pickman_fence_*` caller") is applied here as a hand-listed set again.
Recommendation:
- Scan every tracked `.sh` and `.luau` file outside `z-nile/lib/fence.sh`, `.tracker/`, `*/tests/acceptance/` and the allow-listed fixture specs. Fail any call to a `pickman_fence_*` or `pickman_home_fence` function other than `pickman_fence_all`, `pickman_fence_dirs` and `pickman_guarded`.
- Allow by exact line only the runner's jailed-shell line (`pickman_fence "$1" specs`, and the ceiling loop over `pickman_fence_dirs`' list).
- Mutant: a `pickman_home_fence` call planted in `pickman/check.sh`.

Lesson: testing/guards-move-with-the-working-directory.

### F3 [low] AC18 keeps one file per (id, path) and drops a duplicate silently
Where: `finished.luau`, `sequestered()` (`out[key] = …`, so the last listed path wins).
Evidence: in clone `ac18` I copied `pickman/.tracker/issues/active/f0065` to `pickman/.tracker/issues/f0065` unchanged, and appended `# edited` to the active copy's `check.sh`. AC18 printed `221 sequestered files are their text …`, which is green: `issues/f0065` sorts after `issues/active/f0065`, so only the unchanged copy was judged. `./zn audit` (`error duplicate`) and `./zn check f0065` (`duplicate id`) catch it, and c0120's promoted old-roots spec runs audit, so the gate goes red. That's why this is low.
Recommendation: refuse a key that appears twice at HEAD (or at pre), naming both paths. Spec case: the duplicate above → red. Lesson: architecture/parsers-refuse-ambiguity.

### F4 [low] `pickman_fence_dirs` falls back to `.tracker/` folders when the registry exists but its reader doesn't
Where: `z-nile/lib/fence.sh`, `pickman_fence_dirs` (`if [[ -f $top/z-nile/roots.luau && -f $top/z-nile/projects.toml ]]`).
Evidence: in a tree with `z-nile/projects.toml` and `z-nile/lib/fence.sh`, but no `roots.luau` and no `z-nile/.tracker/`, the set is the top and `pickman` only. `z-nile/`, a registry home, is left out, and nothing is said. A broken `projects.toml` refuses, but a missing reader guesses. No current fixture copies the registry without `roots.luau`, and a runner in such a copy fences its own home anyway, so this is low.
Recommendation: fall back only when `projects.toml` is absent. With the registry present and its reader missing or failing, refuse. Spec case in fence-every-home or registry-home: the registry without `roots.luau` → refuses.

### F5 [low] homes.spec's broken-registry case now passes on any "refusing"
Where: `z-nile/.tracker/issues/c0120/acceptance/homes.spec.luau` (3888c8e3), `has(r.stderr, "refusing") or has(r.stderr, "is under no project root")`.
Evidence (by reading): every fence refusal ends in "refusing", for example `fence: no ref guard at … refusing` or a symlinked `.cache`. So the case would pass if the broken registry were ignored and the run failed for an unrelated reason. The `PASS` check added beside it doesn't tell those apart.
Recommendation (prep): require the registry-specific text: `projects.toml's homes; refusing` (the fence) or `is under no project root` (ac.sh).

## Judged criteria (code mode only)
- JC1: pass, for the new group (the user's "Reviewed by commit group"; `git log --first-parent` shows only new commits on top of 61488eb7, and groups 1-5 are untouched).
  - The override commits (d10faf3, 55dddec, bf85f5e, a0d00f5) touch only promoted specs, and change only marker comments plus stylua's reflow of the expressions the markers left. `override-markers.luau` reports 970/970 marked and 0 misplaced.
  - The hand-written commits (1b835f0, f1592c2, a0eca45, 48cff53, a700819, ca77879, 9c884e7) touch only `z-nile/lib`, `z-nile/check.sh`, `z-nile/tests/lib`, `z-nile/tests/tooling` and `.claude/skills/testing`, all of which are Touched modules.
  - The four merges carry only prep files: c0120's folder and two lesson notes.
  - No commit mixes a move with an edit.
  - F1's override-markers defect concerns trees after a later merge, not this group.

## Prep reference
Not recorded. Prep 3888c8e3's changes in c0120's folder since adbb1188 are the following, and I reviewed them this round:
- 00fb46f: AC18's both-ways walk and last verdict;
- 223f8c1: review-005, refute-005, harvest, override-markers' statement rule;
- 7d27f13: lint;
- 3888c8e: homes.spec.

F1 is a defect in AC18 itself, and F5 is in homes.spec, so this round doesn't pin the prep. With an approving stub in place, AC18 is green at 9c884e7e (221 files) only until the next merge of origin/main.

## Lesson candidates (for the lead)
- review/sequestration-reference-not-a-ref, an addition: a sequestration check that tracks files across lifecycle events must model each event the tracker performs (state move, `done`'s promotion, `paths.rewrite`, compaction) through the tracker's own reader, and its fixture must produce the event with the tracker's own steps, not a hand-written folder move. Check: does the spec's "finished later" case run `done`'s promotion, and does a merge of origin/main that finishes an item keep the check green?
- review (for reviewers): a Recommendation that prescribes how a check models a lifecycle event must name that event's every effect (here, `done` moves `acceptance/` out of the folder). Check: for each event your Recommendation mentions, did you read the code that performs it?

Verdict: changes
