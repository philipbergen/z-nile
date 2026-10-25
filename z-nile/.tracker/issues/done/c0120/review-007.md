# Review 007: c0120 (code mode; the coordinator's round 004 of #107)
Inputs: `origin/impl2-c0120` at 6c58a2e7 (PR #107). The fix delta is `git log --first-parent 9c884e7e..6c58a2e7`: e303d5c, 0605522, f748a93, ef194bf and 6c58a2e. The prep commits merged in are `origin/prep-c0120` 3888c8e3..301a56f3: 5968226, 178454f and 301a56f. I read review-006, refute-006, c0120.md (§1, §12, §14, §14b, Implementation steps, JC1, Guess 18), `./zn lessons --when build --full` and `./zn lessons --skill review --full` first. Every run was in scratch clones under `code-review-c0120b-004/`. Nothing was fetched into, run in or written to the real repository or its `.worktree/*`.
Dropped from review-006: F2, F3, F4 and F5. Each is fixed as refute-006 says (checks below). F1's promotion, compaction and duplicate parts hold. Its merge part doesn't: this round's merge of the whole of today's `origin/main` finds the same mechanism's next hole (F1 here). The refute's simulation placed only R0034 and f0065, which it already expected to finish.
The user's decisions applied: "Reviewer-pinned commit" (AC18) and "Reviewed by commit group" (earlier groups untouched; the new commits are judged as one group).

## What was run
- **Gates**, each in its own clone at 6c58a2e7:
  - `z-nile/check.sh --full`: GATE PASSED. pickman 1162/173, z-nile 845/122.
  - `pickman/check.sh --full`: GATE PASSED. 1162/173.
  - `z-nile/scripts/check.sh --full`: GATE PASSED. 845/122.
- **c0120's `check.sh`** (`./zn sync --fetch`, then `./zn check c0120`): 15/18, and each red is red for its stated reason.
  - AC11: only c0114's `tracker/next` and `z-nile/next (from z-nile)`.
  - AC16: only `busy: cannot read origin/main`.
  - AC18: `no approved review … records a "Prep reference: <sha>"`.
- **`override-markers.luau -- f83441d6`** at 6c58a2e7: `all 970 hunks are marked`. ef194bf's one override, in c0059's adapt.spec, carries its marker, and c0059/adapt is on the Overrides list.
- **Promotion dry run.** I copied c0120's `acceptance/` to `z-nile/tests/acceptance/c0120` and ran `z-nile/check.sh --full`. Static stages: 0 errors, 0 parse errors. pickman 1162/173. z-nile 948/136, with 1 failure: check-paths' live case, which is AC11's expected red (c0114's two paths).
- **Merge simulation, done independently** (clone `msim`, from 6c58a2e7):
  - **The merge.** `git merge -s ours --no-commit origin/main` (09987b2c, 69 commits past the merge-base f50a610a), then main's own changes (`git diff --no-renames f50a610a origin/main`) applied with the §1 and §14b rule:
    - every `tracker/{issues,rafts}/[state/]<id>/…` path goes to `<its project's home>/.tracker/…`, and the project is the one whose root holds the id on HEAD;
    - `tests/acceptance/<id>` goes to `<home>/tests/acceptance/<id>`;
    - `src/`, `tests/…` and `default.project.json` follow the move's renames;
    - a file both sides changed is merged three-way.

    What this brought in: R0034, f0065, R0046 and c0129 done (f0065's and c0129's specs promoted on main); R0035 (f0100, f0101, f0102, f0104), R0045 and R0047 readied; preps #108 (R0044, d0124), #109 (R0035), #110, #111 and #112; and src changes.
  - **Step 12.** `rewrite-finished.luau` changed 0 of 132 files.
  - **AC18**, with an approving stub that pins 301a56f3: **red, 17 of 221** (F1).
  - **override-markers**: **red, 2 of 972** (c0129, F2).
  - **c0114's `done`**, then simulated with the tracker's steps:
    - `git mv` of `acceptance/` to `projects.promotedDir`'s `z-nile/tests/acceptance/c0114`;
    - the folder to `done/`;
    - `paths.rewrite` of its `check.sh` (no change);
    - `c0114-overrides.patch` (`git apply --check` clean);
    - `rewrite-finished` (1 file: `./zn` → `../zn` and `tracker/next` → `../tracker/next`).

    AC18 then showed the same 17 lines and nothing for c0114. override-markers: 2 of 1090, the same two.
  - **Gates on the merged tree.** pickman 1224/183, 0 failed. z-nile 920/134, with 2 failures, both c0114's now-promoted `docs.spec`, from three lesson lines that name old paths. One comes from a lesson new on main. The other two are where I took main's side in a lesson conflict. That's merge content for c0114 (see Notes), not c0120 code. With those lines fixed, `z-nile/scripts/check.sh --full`: GATE PASSED, z-nile 922/134.
- **AC18's new reader, attacked in `msim`.** Lines are counted beyond F1's 17.
  - A promoted f0065 spec edited after `done` → red, `changed (promoted from tracker/issues/active/f0065/…)`.
  - A promoted c0114 spec edited beyond the patch → red, `changed (… with c0114-overrides.patch)`.
  - The patch applied partially (only the first of `window.spec.luau`'s 3 hunks, by `patch(1)` on its pre text) → red.
  - **Duplicate folder.** A copy of `done/f0065` as `issues/f0065`, with the original's `check.sh` edited → refused: `duplicate item folders: …`.
  - **Duplicate folder.** A done item's `acceptance/` restored in its folder beside its promoted copy, and the promoted copy replaced → **green** (F5).
  - **Compaction.** By reading `compacted()` and the real map format (`ids.parseMap`: `old new` lines): a renumbered id whose key is missing refuses. A chain shift (f0066 → f0065) reads as `changed` rather than refused, which is still red. finished.spec's compaction case passes.
  - **A finished `check.sh` that `paths.rewrite` would change differently.** No pre-move `check.sh` names its own item path (I grepped every unfinished `check.sh` at aed3e6f1), so `paths.rewrite` is the identity on every real file. The mutant that drops `paths.rewrite` from AC18's expectation passes finished.spec 5/5 (F4).
  - **`rewrites.world` pinned to the move commit.** The full merge moved f0065, R0034, f0100 to f0104 and R0035, and finished R0034 and f0065. No finished `check.sh` was flagged, and `rewrite-finished` changed nothing, so `moved` holds. `now` is still the live working tree, though. An untracked `pickman/.github/workflows/check.yml` turns R0008's finished `check.sh` red (F3).
- **Review-006 fixes** (by reading and by their cases): F2's repo-fence scan (by `git grep`, only the allowed callers remain), F3 (above), F4 (`projects.toml` without `roots.luau` refuses), F5 (the registry-specific messages). `projects.promotedDir` resolves to the same folder as the old `inHome(homeOf(m), …)`, because `homeOf(reg, "<root>/<id>")` matches the same root prefix.
- **Repository safety (item 8), spot-check.** Clone `g2`, macOS as shipped. A fingerprint (refs, local config, HEAD, `ls-files -s`, worktrees, hooks, stash) was identical before and after each batch.
  - **`check.sh` probes.** A pickman item and a z-nile item. Each fixture `check.sh` sources `z-nile/lib/ac.sh` by path and, inside `check`, runs `rev-parse`, `add -f -N`, `update-ref` and `commit` in `.cache` and `.cache/atk` of the root, `pickman/` and `z-nile/`, plus an `update-ref` from its home.
    - Each runs from the root, `pickman/` and `z-nile/`.
    - Seven environments: none, `GIT_DIR` (absolute, relative `.git`, with `GIT_WORK_TREE`), `GIT_COMMON_DIR`, a ceiling at the root, and a ceiling at root:pickman:z-nile.
    - Every `.cache` sentinel was removed before each run.
    - **42 runs, 0 open.** Each ran from its own home.
  - **Runner probes.** A probe spec in each home ran `rev-parse` and `update-ref` in every home's `.cache` and `update-ref` from the home. Environments: none, `GIT_DIR`, `GIT_COMMON_DIR`, and a ceiling at root:home. **8 runs, 0 open.**

### F1 [high] AC18 judges every other item against the frozen tree before the move, so preps and readies that land on main after it turn AC18 red at the mandatory merge: 17 files with today's `origin/main`, and no later merge can bring it back
Where: `z-nile/.tracker/issues/c0120/acceptance/finished.luau`: `base[key] = { …, rev = pre }` for every id but c0120, and the `if not table.find(wants, now)` / `added` verdicts. c0120.md §14b ("Edits to an item the branch moved follow git's rename at the next merge of main"), Implementation step 12 (a merge of `origin/main` before `done` and after every merge).
Evidence: in `msim`, after merging today's `origin/main` (above) with an approving stub review:
```
pickman/.tracker/issues/active/f0100/acceptance/hud.spec.luau: changed
pickman/.tracker/issues/active/f0100/acceptance/place.spec.luau: changed
pickman/.tracker/issues/active/f0101/acceptance/airborne.spec.luau: added (not in f0101's folder before the move)
pickman/.tracker/issues/active/f0101/{heights,jump,place,sight}.spec.luau, check.sh: changed
pickman/.tracker/issues/active/f0102/acceptance/place.spec.luau: changed
pickman/.tracker/issues/active/f0104/acceptance/place.spec.luau, check.sh: changed
pickman/.tracker/issues/d0124/acceptance/{adapters,drivetop,flow,lobby,top}.spec.luau: added (…)
pickman/.tracker/issues/d0124/check.sh: changed
finished: 17 of 221 sequestered files differ from their text before the move
```
Each one is main's own reviewed change: prep R0044 (#108, 9dfc437: d0124), prep R0035 (#109, db63773) and R0035's ready (388078a: f0100, f0101, f0102, f0104). The branch changed none of them. The reference is `pre` (aed3e6f1), a fixed commit, so these files can never match it again. When R0035 finishes, its promoted specs are judged against `pre` too, and stay red. Any future prep, ready or stop on main that touches an item that existed before the move does the same. That makes AC18 unpassable on any tree that has done step 12, which is where `done` runs it.

Critique: this is the fourth round to find a hole in AC18's reference:
- review-004 F1: a branch ref;
- review-005 F1: presence;
- review-006 F1: promotion;
- now main's own edits.

Each fix taught AC18 one more lifecycle event by hand, and this one can't be taught that way. The tempting fix is "also accept main's text". Done naively (any text that appears anywhere on main), it accepts a branch edit that copies an older main text, and it still leaves override-markers (F2) and the `paths.rewrite` model (F4) to be maintained by hand. c0114's own AC14 already answers the same question the other way. It judges against `git merge-base HEAD origin/main`, which asks "what did this branch change?" and not "what has this file ever been?".

Consequences:
- The reference moves with each merge of main, so AC18 trusts `origin/main` as of the last fetch. That is the same trust AC16 already has. A local `refs/remotes/origin/main` can be moved, so the reference commit must also be an ancestor of HEAD, and CI's fresh fetch is the authority (Guess 18's reasoning: never a ref the author controls alone).
- For a file main changed since the move's base, main's text includes main's own lifecycle effects (ready's and done's `paths.rewrite`, promotion). The expectation for an item finished on main becomes `rewrites.rewrite(<main's text>, home, world)`. The hand model of main's `done` (the `doneThen` / `doneHere` pair and `paths.rewrite`) goes. Only the branch-side events stay modelled: c0114's `done` with its patch, and c0120's own files by the reviewer pin.
- Items captured on main after the move become judgeable too: "added" no longer has to mean "a capture since, not judged".
- A main change and a stack change to the same file: c0114's build changed z-nile items' places before `pre`. The per-key rule must take whichever side changed it, and refuse when both did and they differ.

Recommendation (in prep, as Guess 18 allows for c0120's own files; AC18's wording changes from "its text before the move" to "its text as of the main it merged", which c0120.md §14b already implies, so this is no scope change):
- (a) Let `M = git merge-base HEAD origin/main`, required to be an ancestor of HEAD, and `B = git merge-base pre M`.
- (b) For each key (item, path in the item), with the move's §1 mapping for places:
  - if main's text at `M` differs from its text at `B` (main changed it after the move's base), the reference is `M`'s text, with `rewrites.rewrite` for a `check.sh` that is finished at `M`;
  - otherwise it is `pre`'s text, as now;
  - a key that main and the stack both changed, to different texts, refuses with a message naming both.
- (c) Promoted specs: a spec promoted on main is judged against `M`'s `tests/acceptance/<id>/<rest>`. One promoted on the branch (c0114) is judged as now.
- (d) Drop the `paths.rewrite` composition for main-side `done` (F4 then has nothing left to test).

finished.spec cases, in its fixture with a real "main" branch merged after the move:
- a prep on main edits an unfinished item's `check.sh` and adds an acceptance spec, merged → green;
- the branch then edits that same file → red;
- main readies an item, so its `check.sh` goes through `paths.rewrite` → green;
- main finishes an item and promotes its spec → green, and the branch then edits the promoted spec → red;
- main and the branch change one file differently → refused;
- a local `origin/main` that isn't an ancestor of HEAD → refused.

Mutant: the reference always `pre` (first case red). Re-run the whole-main merge simulation above before claiming it.
Lesson: review/sequestration-reference-not-a-ref.

### F2 [medium] override-markers flags every spec that main promotes for an item captured after the move: c0129's two specs with today's main
Where: `z-nile/.tracker/issues/c0120/override-markers.luau`: `before(id, rest)` searches only `pre`'s tree. A spec with status `A` and no pre-move text falls through to the main diff as one whole-file added hunk.
Evidence: in `msim`, after the merge:
```
pickman/tests/acceptance/c0129/onagain.spec.luau:1
pickman/tests/acceptance/c0129/submits.spec.luau:1
override-markers: 2 of 972 hunks have no "-- c0120 override:"
```
c0129 was captured, prepped and finished on main after the move (R0046, #113). Its specs are main's text, unchanged by the branch. The review-006 F1 (c) fix covered only items that existed at `pre`. JC1's mechanical check now fails after every merge that brings a newly captured item's `done`.
Recommendation: the same base rule as F1's.
- A spec under `*/tests/acceptance` that is new since the renames commit takes its base from `M`'s `tests/acceptance/<id>/<rest>` when main promoted it (mapped to its home by §1), else from its `pre` item text, as now. Only a spec that is in neither place is a whole-file hunk.
- Cases, in a small fixture of their own:
  - an item captured and finished on main after the move, merged → 0 unmarked;
  - one unmarked line added to it on the branch → 1 unmarked.
- Mutant: the main lookup dropped.

### F3 [low] AC18's expectation for a finished `check.sh` depends on the live working tree, untracked files included
Where: `acceptance/rewrites.luau`, `world.now` (`fs.isFile`/`fs.isDir` on `top`, and `ls-files -co` for globs), used by `rewrites.rewrite`. Review-006's pin (`moved` from the move's own renames) fixed only one of the three inputs.
Evidence: in `msim`, `touch pickman/.github/workflows/check.yml` (untracked) → `pickman/.tracker/rafts/done/R0008/check.sh: not its text with exactly the rewrite`. The rewrite would now leave `.github/workflows/check.yml` alone, because it resolves from `pickman/`. A tracked file added to a home by a later merge does the same.
Recommendation: read `now` from the tree of the commit that made the rewrite (JC1 group 2's commit, found as `pre` is) for files finished at `pre`. For files finished by a later merge, read it from the commit that brought them. Never read the working tree. Case: an untracked file at a rewritten path's home-relative place → still green.

### F4 [low] finished.spec never exercises the `paths.rewrite` half of the "finished after the move" expectation
Where: `finished.spec.luau`, `finish()`. f0065's and c0114's fixture `check.sh` is `check AC1 true`, so `paths.rewrite` is the identity. Rules-and-mutants row "AC18 reads … a merged-in done's paths.rewrite …" (run: killed).
Evidence: the mutant `rewrites.rewrite(paths.rewrite(old, { [b.id] = dir }), home, world)` → `rewrites.rewrite(old, home, world)` passes finished.spec 5/5. On the real repository the code is also dead: no unfinished `check.sh` at `pre` names its own item path.
Recommendation: with F1's fix, remove the composition (main's text already carries `paths.rewrite`). Without it, give the fixture's `check.sh` a line that names its own item path (`tracker/issues/active/f0065/acceptance/a.spec.luau`) and list the mutant.

### F5 [low] A finished item whose `acceptance/` is still in its folder hides its promoted copy from AC18
Where: `finished.luau`: the promoted place is read only `if not h`.
Evidence: in `msim` I copied `pickman/tests/acceptance/f0065` into `pickman/.tracker/issues/done/f0065/acceptance` and replaced the promoted `run.spec.luau` with `error("weakened")`. AC18 showed only F1's 17 lines, and `./zn audit` reported 0 errors. override-markers would flag the unmarked hunk, so this is low.
Recommendation: when an item is finished at HEAD and both its folder and `projects.promotedDir` hold `<rest>`, refuse as a duplicate, naming both. Case: the tree above → refused.

### F6 [low] repo-fence's caller scan reads only `*.sh`, `*.luau` and `zn`
Where: `z-nile/tests/tooling/repo-fence.spec.luau`, "every caller of the fence…" (`git ls-files -- *.sh *.luau zn`).
Evidence (by reading): the extensionless git hooks in `z-nile/lib/git-hooks/` and `.github/workflows/*.yml` aren't scanned. Today none calls a fence function (`git grep`, above).
Recommendation: also scan `z-nile/lib/git-hooks/*` and `.github/workflows/*`, or every tracked text file that isn't Markdown. Mutant: a `pickman_home_fence` line planted in `z-nile/lib/git-hooks/post-checkout`.

## Judged criteria (code mode only)
- JC1: pass, for the new group (the user's "Reviewed by commit group"; `git log --first-parent 9c884e7e..6c58a2e7` holds only the five new commits, and groups 1-5 are untouched).
  - e303d5c is hand-written core: `z-nile/engine/{main,projects}.luau`, `z-nile/lib/fence.sh`, two tooling specs, all Touched modules.
  - ef194bf is a single override: c0059/adapt, marked and on the Overrides list. It comes in its own commit.
  - The three merges carry only prep files: c0120's folder and two lesson notes. `git diff 301a56f3 6c58a2e7 -- z-nile/.tracker/issues/c0120` is empty.
  - No commit mixes a move with an edit.
  - F2 is a defect in JC1's instrument on trees after a later merge, not in this group.

## Prep reference
Not recorded. Prep 301a56f3's changes in c0120's folder since 3888c8e3 (5968226, 178454f, 301a56f) are the ones I reviewed this round. F1 and F2 are defects in AC18 and override-markers themselves, so this round doesn't pin the prep.

## Notes for the lead (not findings against c0120's code)
- After the merge, c0114's `docs.spec` (promoted by its `done`) fails on lessons main writes in the old layout. `.claude/skills/testing/lessons/split-paths-still-need-renamed-id.md` (new on main) names `scripts/tracker/compact.luau`. Two ticket-prep lessons that both sides changed name `scripts/tracker.sh capture` and `scripts/ci-verify.sh` on main's side. Step 12 (§14b) doesn't say to fix them, so the PR description should name them at the next merge.
- Main's R0044 (`tracker/issues/done/c0128` compared with `find`'s output) and R0035, R0045 and R0047 are prepped or readied for the old layout. AC16 is red while they are active, and AC11's live case will name any of their `check.sh` paths that don't resolve from the home (§14: re-prep before c0120 is readied).

## Lesson candidates (for the lead)
- review/sequestration-reference-not-a-ref, an addition: a sequestration check judges the branch's own delta (three-way against the main it merged), never a file's distance from a frozen tree, because main keeps changing sequestered files through its reviewed preps and readies. Check: merged with the whole of today's `origin/main`, does the check stay green while the branch has changed nothing?
- review (for reviewers and refutes): a merge simulation merges all of `origin/main`, not the events the author expects. Check: does the simulation's merge commit have `origin/main`'s tip as a parent, and did every path main changed since the merge-base get a place?

Verdict: changes
