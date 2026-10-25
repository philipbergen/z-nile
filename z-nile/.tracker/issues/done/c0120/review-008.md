# Review 008: c0120 (code mode; the coordinator's round 005 of #107)
Inputs: `origin/impl2-c0120` at c601e77e (PR #107). The fix delta is `git log --first-parent 6c58a2e7..c601e77e`: 101fa75, 572a3e5 (merge), 59ee61b (merge) and c601e77. The prep commits merged in are `origin/prep-c0120` 301a56f3..676dfa8e: eeaaf29 and 676dfa8. I read review-007, refute-007, c0120.md (Guess 18, the Rules rows V23 to V25, Implementation steps 12 and 13, JC1), `./zn lessons --when build --full` and `./zn lessons --skill review --full` first. Every run was in scratch clones under `code-review-c0120b-005/`. Nothing was fetched into, run in or written to the real repository or its `.worktree/*`.
Dropped from review-007: F2, F4, F5 and F6, each fixed as refute-007 says (checks below). F1's merge part holds: the whole-main merge is green. F1's trust part doesn't: its Consequences asked that `origin/main` not be the author's ref alone, and AC18 still reads the local ref (F1 here). F3 is fixed for untracked files only (F4 here).
The user's decisions applied: "Reviewer-pinned commit" (AC18) and "Reviewed by commit group" (earlier groups untouched; the new commits are judged as one group).

## What was run
- **Gates**, each in its own clone at c601e77e:
  - `z-nile/check.sh --full`: GATE PASSED. pickman 1162/173, z-nile 846/123.
  - `pickman/check.sh --full`: GATE PASSED. 1162/173.
  - `z-nile/scripts/check.sh --full`: GATE PASSED. 846/123.
- **c0120's `check.sh`** (`./zn sync --fetch`, then `./zn check c0120`): 15/18. Each red is an allowed one, red for its stated reason.
  - AC11: only c0114's `tracker/next (from z-nile)` and `z-nile/next (from z-nile)`.
  - AC16: only `busy: cannot read origin/main`.
  - AC18: `no approved review … records a "Prep reference: <sha>"`.
- **Promotion dry run.** `git mv` of c0120's `acceptance/` to `z-nile/tests/acceptance/c0120`, then `z-nile/check.sh --full`. Static stages clean. pickman 1162/173. z-nile 950/137, with 1 failure: check-paths' live case, which is AC11's expected red. A first try copied the folder instead of moving it. The new `spec-left-beside` audit then correctly failed c0082's real-tree spec and layout, which shows F5's audit works.
- **Merge simulation** (clone `msim`, from c601e77e):
  - **The merge.** `git merge -s ours --no-commit origin/main` (5e1e1b34, 74 commits past the merge-base f50a610a). Then main's own changes (`git diff --no-renames f50a610a 5e1e1b34`) were placed with review-007's `resolve.py` (§1 and §14b: items to their home's `.tracker`, `tests/acceptance/<id>` to the home, the rest along the move's renames). Main's new tooling captures went to z-nile. The 3 conflicting and 3 both-added non-sequestered files (lessons, c0114.md, R0043's harvest) were resolved as unions. The merge commit's parents are c601e77e and 5e1e1b34.
  - What this brought in:
    - R0035's done: f0100, f0101, f0102 and f0104 finished, their specs promoted on main;
    - R0045 and R0047 readied, with c0127 and c0128 prepped;
    - c0132, c0133 and c0134 captured;
    - R0044's prep (d0124);
    - R0034, R0046, f0065 and c0129 done.
  - **Step 12.** `rewrite-finished.luau` changed 0 of 137 files.
  - **AC18**, with an approving stub `review-008.md` that pins 676dfa8e: **green, 246 files**.
  - **override-markers**: all 970 hunks marked.
  - **c0114's `done`**, simulated:
    - the folder to `done/`, and `acceptance/` to `z-nile/tests/acceptance/c0114`;
    - `c0114-overrides.patch` (`git apply --index`, clean);
    - `rewrite-finished` (1 file, c0114's `check.sh`).

    AC18: **green, 246**. override-markers: **all 1088 marked**.
- **Planted branch edits on that tree.** Each one was committed alone on the post-`done` tree, then AC18 and override-markers were run. AC18's results:
  - one line added to d0124's `check.sh` (main prepared it): **red** `changed`;
  - one line added to d0124's `flow.spec` (main prepared it): **red**;
  - one line added to c0132's `check.sh` (captured on main): **red**;
  - one line added to f0100's promoted `blaster.spec` (main promoted it): **red** (override-markers also red, 1 hunk);
  - a *marked* weakening of c0129's promoted spec: **red** (override-markers green, as it should be);
  - one line added to R0035's finished `check.sh` (main finished it): **red** `not its text with exactly the rewrite`;
  - one line added to R0008's `check.sh` (the branch rewrote it): **red**;
  - one line added to c0114's finished `check.sh` (the branch's `done`): **red**;
  - `git rm` of one of f0100's promoted specs: **red** `deleted`.
- **Three-way edge cases.** Each started from a commit on top of 5e1e1b34 that stood in for the next main, set as `origin/main`, then merged:
  - main deletes d0124's `check.sh` (an item there before the move) and the branch keeps it: **red** `added`;
  - main deletes it and the branch deletes it too: green;
  - main renames c0134 to c0135 and the branch follows: green;
  - the same rename, and the branch edits the renamed `check.sh`: **red**;
  - the same rename, and the branch keeps a copy at c0134: green (F5);
  - main deletes c0132's `check.sh` and the branch keeps it: green (F5);
  - main edits f0100's promoted `hud.spec` and the branch doesn't take the edit: **red** (override-markers also red);
  - main edits pre-move-promoted c0002's spec and the branch doesn't take it: AC18 green (outside its scope, by 676dfa8), override-markers **red**, as the Overrides rule wants;
  - **both sides change a file identically**: by reading, `mainChanged and stackChanged and tM == tP` takes M's text, so the branch can't use this to slip an edit through. No hole found.
- **Holes found:** the forged `origin/main` (F1) and the specs moved back out of their promoted place (F2).
- **Mutants** (in clone g3, `finished.spec` from `z-nile/`):
  - V23 (the reference always the tree before the move): killed, 5/6.
  - Dropping the `added` verdict for a file main deleted (`if ref == nil then if h`): **survives, 6/6** (F3).
- **The review-007 fixes:**
  - F2: the c0129 and f0080 cases.
  - F4: the composition is gone.
  - F5: the audit's `spec-left-beside` check (seen in the dry run), plus AC18's duplicate key.
  - F6: the scan now lists `z-nile/lib/git-hooks/*` and `.github/workflows/*`.
- **Repository safety (item 8), spot-check.** Clone g4, macOS as shipped. A fingerprint (refs, local config, HEAD, `ls-files -s`, worktrees, hooks, stash) was identical before and after.
  - Two probe items, a pickman one (f9998) and a z-nile one (c9998). Each `check.sh` sources `z-nile/lib/ac.sh` by path. Inside `check`, it runs `rev-parse`, `update-ref`, `add -f -N` and `commit` in `.cache` and `.cache/atk` of the root, `pickman/` and `z-nile/`, plus an `update-ref` from its home.
  - Each probe runs from the root, `pickman/` and `z-nile/`.
  - Seven environments: none, `GIT_DIR` (absolute, relative `.git`, and with `GIT_WORK_TREE`), `GIT_COMMON_DIR`, a ceiling at the root, and a ceiling at root:pickman:z-nile.
  - **42 runs, 0 open, no `pwn` refs.**
  - A `git ls-remote origin` inside a `check` works under the fence (relevant to F1's fix).

### F1 [high] AC18 takes "main" from the local `origin/main`, which the author can move: an edit to another item's `check.sh`, merged in through a commit that isn't on main, is accepted as main's (repeat of review-007 F1, its Consequences)
Where: `acceptance/finished.luau` lines 181-197: `M = git merge-base HEAD origin/main`, then `if mainChanged then ref = tM`. The only refusal is "origin/main already holds the move". `./zn done` runs `check.sh` without fetching (`cmd.done` → `runCheck`; `refuseStale` is not called first), and CI never runs an item's `check.sh`.
Evidence: in `msim` after c0114's `done`:
- I made commit C on top of the real 5e1e1b34, appending `# forged` to `tracker/issues/d0124/check.sh`. C isn't on GitHub.
- I merged C into the branch with the line placed at `pickman/.tracker/issues/d0124/check.sh`.
- Then `git update-ref refs/remotes/origin/main C`.
- AC18: `finished: 246 sequestered files are their reference (… main 19bd2ec1…)`, **green**, and override-markers green.

The same edit without the forged ref is red (the first planted edit above). finished.spec's own fixture moves `refs/remotes/origin/main` with `update-ref` at every step, so nothing distinguishes a published main from a local one.
Critique: this is the lesson's question exactly ("Can the branch's author make the reference commit…?"). Review-004 F1's `git branch -f prep-c0120 HEAD` was the same hole, high. The user's "Reviewer-pinned commit" closed it for c0120's own files, and the new base reopens it for every other item. Review-007's Consequences required the reference to be checked against CI's fresh fetch, but nothing does that. The tempting fix is "AC16 trusts it too". AC16 only reports who else is busy, though: a stale ref there can't turn a weakened criterion green. Another tempting fix is a reviewer-pinned main sha. That goes stale at once, because step 12 merges main again after the review, and again after `done`.
Consequences: verifying against the remote needs the network at `check.sh` time (`done` publishes anyway). A push to main between the fetch and the check must not refuse spuriously. A force-push on main must refuse. Offline must refuse, never pass.
Recommendation (in prep, as Guess 18 allows for c0120's own files):
- AC18 reads the published tip with `git ls-remote origin refs/heads/main`. That is read-only, and the fence allows it (checked above).
- It refuses when that tip isn't a local commit ("run ./zn sync --fetch").
- It refuses when the tip can't be read.
- It refuses unless `git merge-base --is-ancestor M <tip>` holds.
- override-markers takes M the same way: one helper, both readers (architecture/one-reader-per-format).

finished.spec cases, with a bare repository as the fixture's `origin`:
- local `origin/main` moved to an unpublished commit carrying an edit, and merged → refused;
- the same commit pushed to the bare origin and fetched → green;
- origin unreachable → refused;
- the remote tip not fetched → refused.

Mutant: the ancestry check dropped (the first case goes green).
Lesson: review/sequestration-reference-not-a-ref.

### F2 [medium] An item's specs moved back from their promoted place into its `done/` folder pass AC18, override-markers and the audit, and drop out of the gate
Where: `finished.luau` keys a file by `id|acceptance/<rest>` wherever it sits (`sequestered`'s `put`). The verdict compares only text, never the place the reference has it in. `audit.leftovers`' new `spec-left-beside` check fires only when both copies exist.
Evidence: in `msim` after c0114's `done`, `git mv pickman/tests/acceptance/f0100 pickman/.tracker/issues/done/f0100/acceptance` (main's R0035 promoted those five specs):
- AC18: green, 246.
- override-markers: green, 1088. The files are gone from `*/tests/acceptance`, and the renames commit never had them, so its rename loop doesn't see them either.
- `./zn audit`: 0 errors.

The same move with one spec rewritten to `error(1)` is red (`changed`), so only an unedited move passes. In JC1's content diff (`grep -v '^R100'`) the move is an R100 rename, so it's hidden too. The likeliest way here is an honest one: step 12 places main's promotion by hand, and putting `tests/acceptance/f0100` back in the item's folder passes every check. Done with c0002 (promoted before the move), the move makes override-markers crash (`git show HEAD:pickman/tests/acceptance/c0002/… failed`, line 160) rather than name the file. That is red, but with no message.
Critique: review-007 F5 found one half of this (a copy beside the promoted one). This is the other half: the key ignores where the file is. The tempting fix is the reverse refusal only. Consequences: a spec belongs in an item's folder until that item is done, and in its promoted place after. A `done` mid-flight (c0114's, simulated on this branch) moves both at once.
Recommendation:
- AC18: when HEAD has an item finished and its reference holds `<rest>` (in its folder or promoted), HEAD must hold it at `projects.promotedDir`. A copy in the item's `done/` folder is `not promoted: <path>`. Pre-move-promoted keys have no other checker, so cover them too.
- `./zn audit`: an error for any non-empty `acceptance/` in a `done/` folder (none exists at HEAD or after the simulated merge, so nothing legitimate trips).
- override-markers: skip paths deleted or renamed out of the acceptance folders in its marker loop (`--diff-filter=AM`) instead of crashing.

Cases:
- f0100's specs moved back → red, naming the path;
- c0002's (promoted before the move) moved back → red;
- the audit fixture with a `done/x/acceptance/a.spec.luau` → error.

### F3 [medium] finished.spec never has main delete or rename a file, and the mutant that drops the `added` verdict for a file main deleted passes 6/6
Where: `finished.luau` lines 336-345 (`if ref == nil then if h then … added`). That branch is where a main-side deletion, or a compaction or rename on main, lands. finished.spec's main fixture covers a prep, a ready, a done, a capture-and-done, both sides changing a file, and a moved ref, but no deletion or rename on main.
Evidence: in g3, replacing `if h then` with `if false and h then` passes finished.spec 6/6. The real tree still catches it: main deleting d0124's `check.sh` while the branch keeps it is red. That holds only because the code is right today. The message also says "nor before the move" for a file that *was* there before the move. That's wrong, and nothing pins it.
Recommendation: add these cases to the main fixture:
- main `git rm`s an unfinished item's spec and the branch keeps it → red `added`;
- the branch deletes it too → green;
- main renames an item's folder (a compaction, with its `z-nile/compaction.txt` line) and the branch follows → green, then edits the renamed `check.sh` → red, then keeps the old folder too → red.

Mutant: the line above. Reword the message to "removed on the main it merged" when `p` exists.
Lesson: testing/seed-every-enumerated-case.

### F4 [low] A finished `check.sh`'s expected rewrite still depends on unrelated files: committing one turns AC18 red (repeat of review-007 F3, its tracked half)
Where: `rewrites.world`'s `now` is now HEAD's tree. Review-007 F3 asked for the tree of the commit that made the rewrite.
Evidence: in `msim`, a committed `pickman/.github/workflows/check.yml` gives `pickman/.tracker/rafts/done/R0008/check.sh: not its text with exactly the rewrite`, red. A later merge of main that adds a tracked file at any home-relative path a finished `check.sh` names does the same. It fails closed, so this is low.
Recommendation: as review-007 F3. For a file finished at `pre`, read `now` from the finished-rewrite commit (JC1's group 2, found the way `pre` is). For one finished by a later merge, read it from that merge. Case: a tracked file added at a rewritten path's home-relative place → still green.

### F5 [low] Files of an item captured on main after the move are never judged once main deletes or renames that item
Where: `finished.luau`'s `keys` and `known` come only from `pre`, M and c0120's own set. An id that is in neither `pre` nor M is unknown.
Evidence: in the edge cases above, main deletes c0132's only sequestered file, or renames c0134 to c0135, and the branch keeps the old file (or a copy). AC18 is green. For an item that existed before the move, the same thing is red.
Recommendation: also collect keys from B..M's deletions and renames (`git diff --name-status B M` over the old roots), so an id main removed stays known. Case: an item added and then removed on main, kept by the branch → red.

## Judged criteria (code mode only)
- JC1: pass, for the new group (the user's "Reviewed by commit group"). `git log --first-parent 6c58a2e7..c601e77e` holds only 101fa75, 572a3e5, 59ee61b and c601e77, and groups 1-5 are untouched.
  - 101fa75 and c601e77 are hand-written core: `z-nile/engine/audit.luau`, the new `z-nile/tests/tooling/audit-spec-left.spec.luau` and `repo-fence.spec.luau`, all Touched tooling. c601e77 is a one-line type fix in the new spec.
  - The two merges carry only prep files: c0120's folder and one review-lesson note. `git diff 676dfa8e c601e77e -- z-nile/.tracker/issues/c0120` is empty.
  - No commit mixes a move with an edit, and the group holds no override.

## Prep reference
Not recorded. Prep 676dfa8e's changes in c0120's folder since 301a56f3 (eeaaf29, 676dfa8) are the ones reviewed this round: `finished.luau`, `finished.spec.luau`, `override-markers.luau` (moved into `acceptance/`), `rewrites.luau`, c0120.md's Guess 18, Rules rows, AC18 wording and steps 12 and 13, harvest, review-007 and refute-007. Nothing in them is unreviewed. F1 is a defect in AC18 itself, so this round doesn't pin the prep. For the next round: with a stub approving `review-008.md` that pins 676dfa8e, AC18 was green (246) on the fully merged tree, before and after c0114's `done`.

## Lesson candidates (for the lead)
- review/sequestration-reference-not-a-ref, an addition: "the main it merged" is a ref too. A three-way check takes main from the published tip (`ls-remote`) and the ancestry, never from the local `refs/remotes/origin/main`. Check: with `origin/main` moved locally to an unpublished commit that edits a sequestered file, and merged, does the check refuse?
- A sequestration key that ignores a file's place also has to judge the place: a spec moved back out of its promoted folder keeps its text and loses its gate. Check: with a finished item's promoted specs moved back into its `done/` folder unchanged, does any check go red?

Verdict: changes
