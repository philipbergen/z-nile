# Review 004: c0120 (code mode; the coordinator's round 001 of #107, the redesign)
Inputs: `origin/impl2-c0120` at 41d5fa15 (PR #107), base `origin/prep-c0120` 7871a51b (merge-base with the four groups: aed3e6f1). The groups, one ruling each: (1) f83441d6 renames, (2) 9fab6c87 finished rewrite, (3) d70692da overrides, (4) 9b885a08 hand-written core, (5) 61cd994f Guess 17's deletions plus the prep merges 3d4c2f97, 00ba9908, 757a5fa1, 41d5fa15 (AC18's new rule). The design is `z-nile/.tracker/issues/c0120/c0120.md` with design reviews 001-005. Work done in scratch clones under this folder, never `.worktree/*`.

## What was run
- `z-nile/check.sh --full` passed: pickman 1160/173, z-nile 837/120, 99.6 s. `pickman/check.sh --full` passed (pickman only, 2.9 s). `z-nile/scripts/check.sh --full` passed (z-nile only, 132.7 s). All three ran at 9b885a08; the commits after it change only finished `check.sh` files and c0120's prep files.
- `bash z-nile/.tracker/issues/c0120/check.sh` gave 16/18, at 9b885a08 and again at 41d5fa15. Both reds are red for their stated reasons:
  - AC11 is red only for `z-nile/.tracker/issues/c0114/check.sh: tracker/next` and `z-nile/next` (c0114 is unfinished).
  - AC16 is red only on `busy: cannot read origin/main`: origin/main (b4901d72) has no `z-nile/projects.toml`. The design also says "R0034 is active", but that part is stale: origin/main has no active raft.
- AC18 passed (221 files). An independent check agrees: `git diff -M100% --name-status origin/prep-c0120...HEAD` over every `check.sh` and `acceptance/**` under every root finds nothing that isn't R100 except `done/*/check.sh`. c0120's item folder at HEAD is identical to origin/prep-c0120's.
- Repository-safety attacks. Each ran in its own clone (`mac`: as shipped, jailed; `lin`: `jail()` patched to the Linux path, so no kernel jail and the hooks set). Each attack ran from both homes, and for `check.sh` files also from the root. A fingerprint of refs, index, config and worktrees was taken before and after; it never changed.
  - Inherited `GIT_DIR` (the real `.git`, a foreign repository, relative `.git`), `GIT_COMMON_DIR` (foreign) and `GIT_CEILING_DIRECTORIES` (at the checkout's root, and at root plus home), into the runner and into a `check.sh`: all **closed**. git found no repository in the root's `.cache` or the home's `.cache`, or in folders below them. `update-ref` and `commit` into the real repository were refused (EPERM under the jail, the ref hook on Linux). `pickman_guarded` answered `guarded`.
  - The previous round's Linux probe (`git add -N` under the root's `.cache` from a home): **closed**, from both homes.
  - A symlinked `.cache` at the root or at the home the run is in **refuses**, for the runner (both modes) and for `check.sh`.
  - An unwritable `.cache` with no sentinel and an honest environment **refuses**, at the root and at a home.
  - A runner started from the root refuses. From `scripts/` with a relative runner path it refuses; with an absolute path, see F6.
  - What stays open is reported in F3 (another home's `.cache`, unjailed) and F5 (forged jail markers).
- Group 2: I reran `rewrite-finished.luau` on the parent's finished files. The output is byte-identical to 9fab6c87, and a second run changes 0 of 128.
- Group 5: I reran `delete-criteria.luau` on 61cd994f's parent. The output is byte-identical; a second run changes 0 of 4, and all four files pass `bash -n`.
- Group 1: I recomputed every new path from §1's table and its promoted-folder rule (the item's root after the move). The recomputed set equals the commit's added set, all 794 R100 with no mode changes. Seven pairs look like cross-folder moves; they are identical empty `.gitkeep` blobs that git paired arbitrarily, which is harmless.
- AC18's new own-files rule was attacked in clone `g5` (F1).

### F1 [high] (group 5) AC18 trusts a branch name the executor controls, so c0120's own `check.sh` and specs can be changed without AC18 seeing it
Where: `z-nile/.tracker/issues/c0120/acceptance/finished.luau` (b1a04a1c, dbb00c7a), the `ownBase` loop over `origin/prep-c0120` and `prep-c0120`.
Evidence: in a clone at 41d5fa15 I deleted the AC18 line from c0120's `check.sh`.
- (A) Committed as a plain implementation commit, `finished.luau` says `check.sh: changed`, 1 of 221 differ. That is correct.
- (B) Then `git branch -f prep-c0120 HEAD`: `221 sequestered files are their text before the move`, which is green.
- (C) Make the same edit as a commit on a local `prep-c0120` cut from `origin/prep-c0120`, then merge it into the branch: green, and the merged `check.sh` has no AC18 line.

A push to `origin/prep-c0120` followed by a merge does the same. `ownBase` takes "the newer" merge-base, so any ref by that name that the branch contains becomes the reference for the very files that are sequestered. Today nothing has slipped: the four merges add nothing outside c0120's folder, and that folder equals origin/prep-c0120's. But the criterion can now be passed by a wrong implementation.
Critique: the tempting fix is to read only `origin/prep-c0120`. That still lets the branch's author push the edit to the prep branch and merge it. The rule's premise is that prep commits are reviewed work. The design never says that, and nothing checks it.
Consequences: a fixed reference (a sha written in the issue) has to change every time the prep legitimately changes after the move, which is how Guess 17 reached the branch. That brings back the same problem: whoever changes the sha changes what AC18 accepts.
Recommendation: escalate to the user, since this is AC18's rule (a sequestered file), and the options are:
- (a) judge c0120's own files against the prep commit the last approved design review or code review names (a sha recorded in `review-NNN.md`, which only a reviewer writes);
- (b) keep the tree before the move as the base, and accept exactly the prep diffs the user approved, listed by sha;
- (c) keep the rule and add to the review skill's code-mode item 2: `git diff origin/prep-c0120 HEAD -- <c0120 folder>` must be empty, and every prep commit merged after the move must have its own review.

Whichever is chosen, the spec case is the one above: a local `prep-c0120` at HEAD carrying an edit to `check.sh` turns AC18 red.

### F2 [medium] (group 4) repo-fence's allow-list names c0120's promoted specs by a path that never exists, so the z-nile gate goes red at `./zn done c0120`
Where: `z-nile/tests/tooling/repo-fence.spec.luau:144`, `["tests/acceptance/c0120/homes.spec.luau"]`. There is no entry for `runner-home.spec.luau`.
Evidence: since c0120 the scan records paths relative to the root (`z-nile/tests/acceptance/c0120/…`), so the key matches nothing. I copied c0120's specs into `z-nile/tests/acceptance/c0120/` (what `done` does) and ran repo-fence from `z-nile/`. It fails with 8 names: homes.spec names `GIT_CEILING_DIRECTORIES`, `PICKMAN_TEST_FENCE`, `PICKMAN_FENCE_`, `GIT_DIR`, `GIT_CONFIG_` and `sandbox-exec`; runner-home.spec names `GIT_CEILING_DIRECTORIES` and `PICKMAN_TEST_FENCE`. `promote-check` runs only type checks, the meta spec and the promoted specs, never repo-fence, so RC0 and every `check.sh` pass and the failure surfaces only at `done`.
Critique: the obvious fix is to correct the key and add runner-home's entry. That fixes this case, but a stale key still fails silently: nothing says an entry names a file.
Consequences: a check that every key names a file would go red today on c0114's two keys, whose specs aren't promoted on this base. The check has to accept an unfinished item's spec at the place it will be promoted to.
Recommendation: key `z-nile/tests/acceptance/c0120/homes.spec.luau`, and add `z-nile/tests/acceptance/c0120/runner-home.spec.luau` with its two names and reasons. Add a repo-fence case: every `ALLOWED` key is a tracked file, or an unfinished item's acceptance spec at its `promotedDir`.

### F3 [medium] (group 4) An unjailed run fences its own home's `.cache` and the root's, but not the other homes'
Where: `z-nile/tests/lib/fence.luau` `fence.enter` (the root's refusals and sentinel when `ROOT ~= here`); `z-nile/check.sh` (the homes get the link sweep only).
Evidence: in `lin`, from `pickman/`, a spec ran git in `z-nile/.cache/atk5` and in `z-nile/.cache` itself, and `git rev-parse --absolute-git-dir` printed the real `lin/.git`. `git add -N` there was stopped only because `.cache/` is ignored; `-f` would not be. With `z-nile/.cache` symlinked outside the checkout, the pickman run went ahead and the spec wrote through the link. Under the macOS jail both writes are refused. No current spec writes into another home's `.cache` (grep), so this is not high. It is the same class as design review 005 F2 and the earlier "a home not fencing the toplevel `.cache`". The design lists it only as a reasoned row ("the tripwire counts a worktree under any `.cache`"), and the tripwire sees worktrees, not git finding the repository.
Critique: the guards cover a hand-listed set of folders (the run's home, then the root, added after a review). A third home gets nothing until a review finds it.
Consequences: fencing every home from every run means that, unjailed, a pickman run writes `z-nile/.cache`'s sentinel. The write is a rename of the same content, so it is harmless next to a concurrent z-nile run. It must happen before the jail is entered, and the jail must stay limited to the run's own home. The gate also writes `<home>/.cache/check*.rbxl` through `replace-file.pl` before any runner's refusals look at that `.cache`. So a home whose `.cache` is a symlink (which Linux specs can leave) gets the build written through it. The root got refusals in the gate; the homes did not.
Recommendation: derive the set from the registry (`z-nile/roots -- --projects`). `fence.enter` runs refusals and sentinel for the root and every home, with the ceiling naming all of them. The gate runs `pickman_fence_refusals` for every home's `.cache` before its first write there. Add runner-home cases: from each home, git in every other home's `.cache` and below finds no repository, and a symlinked other-home `.cache` refuses. Run them with `PICKMAN_TEST_JAIL` both `sandbox-exec` and `none (…)` (lesson testing/host markers).
Lesson: the build lesson "When a check's working directory moves, every guard tied to a folder moves with it".

### F4 [medium] (group 3) Many override spots have no `-- c0120 override:` marker, so JC1's group 3 is not met
Where: d70692da.
Evidence:
- 8 of the 101 files have no marker at all: pickman c0002/affected-place, c0015/docs, c0015/tools, c0041/src-aliases, c0063/narrowed, c0064/docs, c0103/narrowed, f0054/docs.
- Of 904 hunks, 379 have no marker in the hunk or within 3 lines above it (247 still lack one within 10 lines).
- These include real changes, not only paths:
  - c0015/workflow renames a case title ("…no with, shell, continue-on-error or extra if; pickman's from its home") and adds `working-directory` assertions on `steps[5]`, with no marker at either spot;
  - the paths-ignore change in that file is marked;
  - f0061/lobby-tooling replaces the two `par_start rojo build` matches with a loop match, 7 lines below its marker.

Every file is named in Overrides: the 101 equal the measured 113 minus c0114's 12, and no unlisted file appears.
Critique: JC1 requires "every changed spot marked", because group 3 is reviewed by its markers. A single marker per file, or a marker defining a variable used further down, leaves the reader to find the spots.
Consequences: a marker inside a multi-line case title splits a frozen case name (the c0062 lesson in the Verification log), so markers go above `it(`. A case-title change in a promoted spec is itself an override and needs its reason.
Recommendation: mark every changed spot (the hunk, or the line above the enclosing statement or `it(`). Record a mechanical check in the Verification log: every `-U0` hunk has a marker in the hunk or within N lines above it.

### F5 [low] (group 4) The jail waiver keys on markers anyone can forge
Where: `z-nile/lib/fence.sh` `pickman_home_fence`. `ac.sh` also uses it for the root.
Evidence: in `lin`, outside any jail, I made `pickman/.cache` (and in another run the root's `.cache`) unwritable and removed the sentinel, then set `PICKMAN_TEST_JAIL=sandbox-exec PICKMAN_FENCE_SPECS=1 PICKMAN_TEST_FENCE=<elsewhere>`. The fence printed "the jail refused …; its ceiling and every other guard hold". git in that `.cache` then found `lin/.git`. With an honest environment it refuses. It is low because it needs a forged environment, which the guards already trust: on this code, and on main, `PICKMAN_FENCE_HOOKS=<a folder of no-op hooks>` turns the ref guard off. With it, `update-ref` into the real repository succeeded in `lin` (I reproduced this, then deleted the ref). The code also matches the written design (row H7; homes.spec uses `chmod 555` as the jail's stand-in).
Recommendation: escalate to the user, or capture an issue. Either check that the jail is real (the sandbox's EPERM versus chmod's EACCES), which needs homes.spec's stand-in re-prepped, or name in the testing skill's "Caught only by review" that the guards trust `PICKMAN_TEST_*`, `PICKMAN_FENCE_*` and `PICKMAN_FENCE_HOOKS` from their environment.

### F6 [low] (group 4) The runner accepts any top-level folder as a home, not only the registry's
Where: `z-nile/tests/run.luau` (`HOME`).
Evidence: from `scripts/`, `lune run <absolute>/z-nile/tests/run` fenced `scripts/.cache`, writing the sentinel and `gh-none`, then died with "Failed to resolve tests/run". §4 says a folder that is no project's home refuses, with the message "(z-nile/projects.toml)". The guards still held. Separately, `lune run ../z-nile/tests/run` refuses even from a home, because `debug.info` keeps the `..` unnormalized.
Recommendation: refuse unless `HOME` is a home in `projects.load(ROOT)`, and normalize the runner's path. Add a runner-home case from a non-home top-level folder.

### F7 [low] (group 4) Documents and paths
- The tracker skill's compaction bullet names "`tests/acceptance/`, `pickman/tests/acceptance/`". The root's `tests/` is gone; it should name `z-nile/tests/acceptance/`.
- Both doc templates hard-code "(pickman/.tracker/)" for every project's architecture map.
- `find` and `members` run outside the checkout print root-relative paths, but §3 says absolute.
- `pickman/.luaurc` lacks the `znile` alias §5 lists. It works through the root's, but it isn't what the design says.
- The root `selene.toml` is edited in group 4. Only U5 names that edit, not Touched modules.

## Rulings by group
- (1) Renames, f83441d6: **pass**. 794 R100; the classification is exactly §1's rule.
- (2) Finished rewrite, 9fab6c87: **pass**. Exactly the tool's output, and idempotent.
- (3) Overrides, d70692da: **changes** (F4). The file set is right; the markers are not.
- (4) Hand-written core, 9b885a08: **changes** (F2, F3; low F5-F7). Every attack the brief listed refuses.
- (5) Guess 17 and the prep merges: the deletions (61cd994f) **pass**: exactly `delete-criteria.luau`'s output, 9 lines, 4 files, idempotent. The merges carry only prep files. AC18's new rule gets **changes** (F1).

## Judged criteria (code mode only)
- JC1: fail. Groups 1, 2, 5 and 4 each hold only their own kind of change, and the content diff holds only paths the document names (the root `selene.toml` is named only in U5, F7). Group 3 does not meet "every changed spot marked `-- c0120 override:`": 8 files have no marker and 379 of 904 hunks have none within 3 lines (F4).

## Lesson candidates (for the lead)
- review/ownbase-by-branch-name: a sequestration check must never take its reference from a ref the branch's author can move. Check: can the author make the reference commit (a local or pushed branch, a merge) that the check judges sequestered files against?
- testing/allowlist-keys-exist: an allow-list keyed by path needs a case that every key names a file (or a known future one). Check: after a move or a promotion, does every key still match a file the scan visits?

Verdict: changes
