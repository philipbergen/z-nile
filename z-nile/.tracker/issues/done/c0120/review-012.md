# Review 012: c0120 (code mode; the coordinator's round 009 of #107)
Inputs: `origin/impl2-c0120` at 1cf6ad92 (PR #107). The fix delta is `git log --first-parent 8f0aee61..1cf6ad92`: 8cbf0c6 (busy's scoped exemptions, `compact.busyRefNames`), 67e0459 (the mode restore), 5e05de4 (the tracker skill's compaction line), and the merges f6dcde5, 4ebc6d3, d09c1cf, f7e33d4, 69619a6 and 1cf6ad9. The prep merged in is `origin/prep-c0120` cc6061b3..0ac9b8bb, which includes AC18's anchored places and mode comparison, and the two fixes from the simulated done (d948683: the overrides patches read from the pinned prep's folder after done; bcf429c: `modeOf`'s type casts). `git diff 0ac9b8bb HEAD -- z-nile/.tracker/issues/c0120` is empty, and each merge's c0120 folder and lessons equal its prep commit. I read review-011 and refute-011 first, then c0120.md's new Guess 20 bullets, Rules rows V41 to V49 and its Limits note, and `./zn lessons --when build --full`. Every run was in scratch clones under `code-review-c0120b-009/`, with a bare mirror of GitHub as `origin` for the merge simulation. The real repository was only read, with `git ls-remote`.
Dropped from review-011: F1 to F5, each fixed as refute-011 says (checks below).
The user's decisions applied: "Reviewer-pinned commit", "Reviewed by commit group", "Reviewed overrides patch", "Re-prep R0044 after; exempt the stack", "Named exemptions you approve", and the coordinator's "detect, not prevent" limit (a finding that needs a deliberately hostile author is a documented limit).

## What was run
- **Gates**, each in its own clone at 1cf6ad92:
  - `z-nile/check.sh --full`: GATE PASSED. pickman 1404/206, z-nile 959/143.
  - `pickman/check.sh --full`: GATE PASSED. 1404/206.
  - `z-nile/scripts/check.sh --full`: GATE PASSED. 959/143.
- **c0120's `check.sh`** (all origin refs fetched, then `./zn check c0120`): 17/18. **AC16 is green.** The only red is AC18, `no approved review … records a "Prep reference: <sha>"`, which is the expected red before this review.
- **busy's scoped exemptions (review 011 F1, F2, F5).**
  - `./zn busy tracker src tests` exits 0. It names on stderr seven refs as `ignored for c0120's freeze: … (stacked on its prep)`: impl-c0115, impl-c0120, prep-c0115 to prep-c0118, prep-c0121. Each one is a listed stacked prep or has history holding the prep, as the user decided.
  - `./zn busy` with no paths exits 1 and lists the same eight branches `./zn compact` refuses on.
  - The end condition is `cat-file -e origin/main:tracker/rafts/done/R0001/check.sh`, the same mark AC18 uses, so the exemption ends when the move lands, squashed or not.
  - `busyRefs` keeps its short names for compaction, and `busyRefNames` gives full refnames to busy. Only `refs/remotes/origin/` loses `origin/`.
  - The worktree loop builds `refs/heads/<on>`, and a detached worktree (`on == ""`) is never exempt.
  - I spot-ran three mutants and freeze.spec killed each one:
    - worktree exemption dropped (V44): 1 red, line 244;
    - the default paths exempt (V41): 2 red;
  - from finished.spec: the mode comparison dropped (V49): 1 red, line 519.
- **AC18's places and mode (review 011 F3, F4).**
  - The `where` list is now `:(literal)` paths: the three trees' roots plus the retired `tracker/`, `issues|rafts` × `''|active/|done/`, the promoted folders, and the root's `tests/acceptance/`. There is no glob left.
  - `modeOf` compares each file's `ls-tree` mode with its reference's: `ownBase` for c0120's own files, M when main changed the file, and `pre` otherwise.
  - `git diff -M100% --summary origin/main...HEAD` shows **0** `mode change` lines. 67e0459 is mode-only (24 files, 0 lines changed, 24 × `100644 => 100755`).
- **AC18 with my review in place.** In the clone at 1cf6ad92, with this review's three pin lines at `z-nile/.tracker/issues/c0120/review-012.md`: **green, 251 files**. Its output names `before the move aed3e6f1…, main 9734bb65… from https://github.com/philipbergen/pickman.git`, which is the right origin URL.
- **Pins verified.**
  - Prep 0ac9b8bb is `origin/prep-c0120`'s tip and an ancestor of HEAD, and HEAD's c0120 folder equals it.
  - Move f83441d6 is 86th on HEAD's first-parent line. All 794 of its changes are R100, with 0 `mode change`.
  - Core 9b885a08 is 83rd on that line, three after the move, with the subject `c0120: run each project from its home …`.
- **Simulated done** (clone `msim`, from the mirror). `git ls-remote` gives origin/main **d3d8f137**, the mirror's main.
  - `git merge origin/main`: clean, and still no `mode change` against main.
  - With the stub approving review committed, `./zn check c0120` is **18/18**. override-markers marks all 1104 hunks, and `./zn audit` reports 0 errors and 0 warnings.
  - Then done's tree by hand: `acceptance/` → `z-nile/tests/acceptance/c0120`, and the folder → `z-nile/.tracker/issues/done/c0120`, committed.
  - On that tree, `z-nile/check.sh --full` gives **GATE PASSED** (pickman 1404/206, z-nile 1067/157), `./zn check c0120` is **18/18** (AC18 green after done, which confirms d948683's fix), and `./zn audit` reports 0 errors and 0 warnings. The promoted gate type-checks `finished.luau`, which confirms bcf429c's fix.
- **Sequestration (item 2).** Since 8f0aee61, the only `check.sh` changes outside c0120's folder are 67e0459's mode restores. They match main's modes and AC18 accepts them.
- **Repository safety (item 8).** The delta changes no fence file. The engine change runs only read-only git (`for-each-ref`, `diff`, `rev-parse`, `merge-base`, `cat-file -e`, `branch --show-current`).
- **Lessons.**
  - seed-every-enumerated-case: both loops are seeded now (branches and worktrees), and so are both path modes (given and none).
  - no-vacuous-pass: the mode check is skipped only when there is no reference, and every judged key has one.
  - pin-call-site-arguments: `#pos > 0` is pinned by the no-paths case.
- **A documented limit, not a finding.** `modeOf` parses `ls-tree` without `-z`, so a path git would C-quote doesn't match. That can only turn a file red, never green, and no sequestered path needs quoting.

## Judged criteria (code mode only)
- JC1: pass, for the new group (the user's "Reviewed by commit group"). `git log --first-parent 8f0aee61..1cf6ad92` holds only the commits listed under Inputs, and groups 1 to 4 are untouched: the pinned move and core are as above. Each commit is one kind:
  - 8cbf0c6: the engine's busy and the skill line documenting it;
  - 67e0459: modes only;
  - 5e05de4: the skill's wording only;
  - each merge: prep only, equal to its second parent in c0120's folder and lessons, with no other path changed.

  No commit mixes a move with an edit, and the whole diff holds no `mode change`.

## Prep reference
Prep reference: 0ac9b8bb6414e76ef32349e3a67c184445d3f747
Move commit: f83441d629761a0da5d539a80c24f8abbca62578
Core commit: 9b885a0875ff70bfb86a94f30cb0a4759c541ee3

Verdict: approve
