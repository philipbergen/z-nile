# Review 011: c0120 (code mode; the coordinator's round 008 of #107)
Inputs: `origin/impl2-c0120` at 8f0aee61 (PR #107). The fix delta is `git log --first-parent b99ba63c..8f0aee61`: the commits b0b9c39 and dbb80c4 (`z-nile/engine/main.luau`, the freeze's exemptions), 8fc5bad (step 12: c0114's AC13) and d8253e6 (the override markers), and the merges 22aa5b7, d8e78d4, 04b79ad, e3c5328, 9c7d951, 4377fbe and 8f0aee6. The prep merged in is `origin/prep-c0120` 56fc62dc..cc6061b3: a610ff7, ee2216b, 13364e5, ea33787, 43c77bd, 791b6b4 and cc6061b. `git diff origin/prep-c0120 HEAD -- z-nile/.tracker/issues/c0120` is empty, and each merge's c0120 folder equals its prep commit. I read review-010 and refute-010 first, then c0120.md (Guesses 18 to 20, the new Rules rows), `./zn lessons --when build --full` and the review lessons. Every run was in scratch clones under `code-review-c0120b-008/`, each with a bare mirror of GitHub as its `origin`. Nothing was fetched into, run in or written to the real repository, which was only read, with `git ls-remote`.
Dropped from review-010: F1 to F4, each fixed as refute-010 says (checks below). F2 was fixed more widely than recommended ("the item's own places", any root or state). Its soundness is judged under "The supersede rule" below, and its missing case is F3.
The user's decisions applied: "Reviewer-pinned commit", "Reviewed by commit group" (earlier groups untouched; the new commits are judged as one group), "Reviewed overrides patch", "Re-prep R0044 after; exempt the stack" and "Named exemptions you approve".

## What was run
- **Gates**, each in its own clone at 8f0aee61:
  - `z-nile/check.sh --full`: GATE PASSED. pickman 1404/206, z-nile 959/143.
  - `pickman/check.sh --full`: GATE PASSED. 1404/206.
  - `z-nile/scripts/check.sh --full`: GATE PASSED. 959/143.
- **c0120's `check.sh`** (`./zn sync --fetch`, then `./zn check c0120`): 16/18. AC11 is now green, because R0044's and d0124's check.sh blobs (f989acf1, 3145713e) are in `RESTAMPED` and equal origin/main's. The two reds are the allowed ones:
  - AC16: only `origin/prep-skill-lessons`;
  - AC18: `no approved review … records a "Prep reference: <sha>"`.
- **AC18 with a stub approving review** (uncommitted) that pins prep cc6061b3, move f83441d6 and core 9b885a08: **green, 251** (`before the move aed3e6f1…, main 9734bb65…`, from the mirror).
- **The anchors are the real groups 1 and 4.**
  - f83441d6 is the commit that removed `tracker/rafts/done/R0001/check.sh` (`git log -1 -- MARK`), on HEAD's first-parent line. Its 794 changes are all R100, and its modes are unchanged.
  - The next three first-parent commits are 9fab6c87 (rewrite-finished's output), d70692da (overrides) and 9b885a08 (`c0120: run each project from its home …`).
- **Review 010's re-anchor attack** (clone `atk`, the stub review):
  - control: c0128's AC4 set to `true` gives AC18 **red**, `changed`;
  - then MARK restored from aed3e6f1, removed again, two empty commits and a forged `c0120: run each project from its home (again)`: **refused**, `the move is not the one review-011.md pins (f83441d6…)`.
- **Wrong pins**, each refused:
  - move = f83441d6^ or 9fab6c87: `the move is not the one … pins`;
  - core = 9b885a08^, the merge after it, or that merge's second parent (off the first-parent line): `the core is not the one … pins … three after the move`;
  - no Core line, or a non-hex Move line: `records no "Move commit: <sha>" and "Core commit: <sha>"`;
  - two Move lines: `records more than one …`.

  Short shas resolve and pass, which is right. `pre` is the parent of the pinned move, so it is pinned too.
- **The supersede rule** (`:(glob)**/<id>/<inner>`, plus the promoted folder, over `B..M`). I looked for a way a blob at another place of the same item could let an edit through:
  - `landed` can only turn a refusal into "main's published text at M (with the pinned patch)". That reference is not the author's, so no branch edit gets in through it. The worst case is that a stack change is dropped in favour of main's newer text, which is the rule's intent when the stack's text really reached main.
  - For the stack's text to show up at another of the item's places, main must have committed that exact blob there between B and M. A rename that keeps the blob changes no occurrence count, so `--find-object` doesn't match it.
  - No path in any ref's history has an id-named folder outside `<root>/(issues|rafts)/…` or `tests/acceptance/<id>/`, so the unanchored `**/` matches nothing else today (F3).
  - Mutant: the pathspec narrowed back to `p.path` and `m.path` (review 010's literal fix). The live AC18 is **red** (c0114's spec and check.sh refuse, 3 files). finished.spec stays **green, 6/6** (F3).
- **The freeze's exemptions** (scratch clone, real refs plus crafted local branches, each adding `src/zz-*.luau`):
  - listed (block): `spoof-onmain` (cut from 9734bb65, a commit of the prep that main already has), `prep-c0115x`, `proto-c0118.bak` and `PROTO-C0117`;
  - ignored: `stale-prep` (cut from the old prep commit 56fc62dc) and `merged-prep` (unrelated work that merged `origin/prep-c0120`). Both are "history holds a commit of origin/prep-c0120 that main doesn't", as the user decided;
  - ignored: a local branch named `origin/proto-c0117` (F5);
  - with no paths (compaction's set), `./zn busy` prints nothing and exits 0, while `compact.busyRefs` (what `./zn compact` refuses on) names `origin/impl-c0120` and `origin/prep-c0115` to `origin/prep-c0120` (F1);
  - mutant: the worktree exemption (dbb80c4) dropped: freeze.spec **6/6 green** (F2). Sanity mutant, the branch exemption dropped: 2 red, so the spec runs this engine.
- **Review 010's other fixes**:
  - F3: c0114's AC13 now reads `-- ../tracker/next ./next` from `z-nile/`, which is right. 8fc5bad is rewrite-finished's output alone, and AC18 accepts it.
  - F4: the three marker pairs in `main-overrides.patch` and the overridden files now say "the spec runs from z-nile/, its home" above `local home` and "its fixtures go in its home's .cache" above `local base`. d8253e6 is exactly the patch, and override-markers marks all 1104 hunks.
- **Promotion dry run.** `git mv` of c0120's `acceptance/` to `z-nile/tests/acceptance/c0120`, then `z-nile/check.sh --full`: pickman 1404/206, z-nile 1065/157, **GATE PASSED**. check-paths' live case is green now that R0044 is restamped.
- **Fence spot-check (item 8).** Clone g1, macOS as shipped. Round 009's probe item c9998 (rev-parse, update-ref, add and commit in `.cache` and `.cache/atk` of the root, `pickman/` and `z-nile/`, plus an update-ref from its home) was run from the root, `pickman/` and `z-nile/`, with no environment and with an absolute `GIT_DIR`: **6 runs, 0 open**. The fingerprint (refs, local config, HEAD, `ls-files -s`, worktrees, hooks, stash) was identical before and after, with no `pwn` refs. The delta changes no fence file. The engine change runs only read-only git (`rev-parse`, `merge-base`, `branch --show-current`).
- **Whole-main merge simulation** (clone `msim`). origin/main by `git ls-remote` is **d3d8f137**, unchanged since round 010.
  - `git merge origin/main`: clean.
  - AC18 with the stub: **green, 252** (`main d3d8f137…`). override-markers: all 1104 hunks marked. `./zn audit`: 0 errors, 0 warnings.
  - `./zn check c0120`: 17/18. Only AC16 is red (`origin/prep-skill-lessons`).
  - The gate: pickman 1404/206, z-nile 959/143: **GATE PASSED**.
- **Sequestration (item 2).** Since b99ba63c, the files changed outside c0120's own folder are:
  - c0114's done `check.sh` (8fc5bad, the finished rewrite, AC18-checked);
  - the three overridden specs (d8253e6, the pinned patch, AC18-checked).

  On the whole diff, see F4.

### F1 [medium] `./zn busy` now skips the stacked and approved branches for every path set, so with no paths (compaction's set) it reports nothing while `./zn compact` refuses on six branches; the tracker skill's `busy` row and its compaction rule are now false, and the exemption stays in the engine after c0120 lands
Where: `z-nile/engine/main.luau` `cmd.busy` (`if stackedOnC0120(ref) then continue end`, and the worktree loop), against `compact` (`compactLib.busyRefs`, unfiltered). Tracker skill line 19 ("`./zn busy` lists what holds them") and line 76 ("Lists … every branch, local or on origin, that changes them … Without paths it guards what compaction guards").
Evidence: in a clone at 8f0aee61 with today's refs, `./zn busy` prints nothing and exits 0. `compact.busyRefs("impl2-c0120")`, which `./zn compact` refuses on, returns `origin/impl-c0120, origin/prep-c0115, origin/prep-c0116, origin/prep-c0117, origin/prep-c0118, origin/prep-c0120`. The user's decisions (Guess 20) exempt these branches from **the freeze** (AC16, `./zn busy tracker src tests`). Nobody decided the general command should hide them. The names are fixed in the engine with no end condition, so after landing `./zn busy` keeps hiding any branch called prep-c0115 … proto-c0118 for any paths.
Critique: the tempting fix is a line in the skill saying busy skips them. That keeps a read-only diagnostic that disagrees with the command it documents, and keeps a one-item rule in the engine for good.
Consequences:
- AC16 is sequestered and calls `zn busy tracker src tests`, so the exemption must stay active for exactly that call.
- freeze.spec's new case asserts `has(r.stdout, "stacked-work") == false`, so any report of what was ignored must go to stderr, or the case must change in prep.
- The exemption must end when origin/main holds the move. Otherwise a future prep reusing one of these names is silently exempt.
Recommendation:
- Apply `stackedOnC0120` only to the move's freeze: explicit paths, and only while origin/main doesn't hold the move (for example while `origin/main:tracker/rafts/done/R0001/check.sh` exists). With no paths, never apply it, so busy agrees with compaction.
- Print each ignored ref to stderr (`ignored for c0120's freeze: <ref> (stacked on its prep | approved by name)`) without counting it toward the exit code.
- Update the tracker skill's `busy` row (and the read-only list, if its wording changes).
- Cases in freeze.spec:
  - no paths: a stacked branch is listed, exit 1;
  - `tracker src tests`: the same branch is ignored, with its stderr line, exit 0;
  - main holding the move: the exemption is off.
- Rules rows and mutants: the default-path exemption (killed by the first case); no end condition (killed by the third).
Lesson: tracker/exhaustive-lists-name-new-things (the skill's `busy` row describes what the command lists).

### F2 [medium] The worktree half of "Named exemptions you approve" (a worktree on an ignored branch is ignored) has no case and no Rules row: dropping it leaves freeze.spec green
Where: `cmd.busy`'s worktree loop (`local on = … branch --show-current`; `if on ~= "" and stackedOnC0120(on) then continue end`, dbb80c4). c0120.md Guess 20 ("and a worktree on any branch the function ignores"). The Rules row for Guess 20 lists V33 to V35, all about branches.
Evidence: mutant `if false then` in place of that condition: freeze.spec **6 passed, 0 failed**. The only worktree case uses `wt-work`, which is not exempt, so it kills only the opposite mutant ("every worktree ignored"). Two edges are unpinned: a detached worktree (`on == ""`) and a worktree on a local branch whose name merely resembles an approved one.
Critique: this is a user decision with no case. A later edit to the loop (for example, reading the branch with a different command whose output is `HEAD` for a detached worktree) changes it unseen.
Consequences: the case needs a worktree with uncommitted changes under a frozen path on an approved branch, one on a look-alike name, and a detached one. With F1's fix, each ignored worktree also prints its stderr line.
Recommendation: in prep, add a freeze.spec case:
- a worktree on `proto-c0117` with an uncommitted change under `src/`: not listed;
- one on `proto-c0117-copy`: listed;
- one detached at main with a change: listed.

Add the row: "a worktree on a branch the freeze ignores is ignored (Guess 20)", with mutants "the worktree exemption dropped" and "a detached worktree exempt".
Lesson: testing/seed-every-enumerated-case (the code walks branches and worktrees; the fixture seeds the exemption for branches only).

### F3 [low] The supersede rule's widened places (cc6061b: `**/<id>/<inner>` in any root or state) have no fixture case: review 010's narrower pathspec passes finished.spec, and only the live AC18 run on c0114 tells them apart
Where: `finished.luau`, the `where` list. c0120.md Guess 18 ("at that item's own places, in any root or state"). The V39 row ("the pathspec dropped") is killed by f0076, but nothing kills "the pathspec too narrow".
Evidence: mutant `where = { p.path, m.path }`. The live AC18 is red (c0114's `finished.spec.luau` and `check.sh` refuse). finished.spec is 6/6 green. The glob is also unanchored: `**/<id>/<inner>` matches an `<id>/<inner>` at any depth, not only `<root>/issues|rafts/[active/|done/]<id>/`. No such path exists in any ref's history today.
Recommendation: in prep, add a fixture case. The stack's text for an item reaches main at the item's folder in the other root, or in `done/`, between B and M, and main then changes it: main's text supersedes (green). Kill "the pathspec only at p.path and m.path" with it. Anchor the glob to the registry's roots, for each root `<root>/{issues,rafts}/**/<id>/<inner>`, and add a row.
Lesson: testing/seed-every-enumerated-case.

### F4 [low] 24 sequestered `check.sh` files lose their executable bit against main (100755 → 100644) since the merge 95cc2a4, which neither item 2's R100 listing nor AC18 (blobs only) sees
Where: the files are:
- pickman: `pickman/.tracker/issues/{c0128,done/c0129,done/f0065,done/f0100,done/f0101,done/f0102,done/f0104}/check.sh` and `pickman/.tracker/rafts/{R0044,R0045,done/R0034,done/R0035,done/R0046}/check.sh`;
- z-nile: `z-nile/.tracker/issues/{c0122,c0123,c0132,c0134,c0135,c0136,c0137,done/c0114,done/c0127,done/c0131}/check.sh` and `z-nile/.tracker/rafts/done/{R0043,R0047}/check.sh`.

The move f83441d6 keeps every mode. The bits were lost in the merge 95cc2a4 (round 010's group), which re-placed main's new and changed items.
Evidence: `git diff -M origin/main...HEAD --summary` shows 24 `mode change 100755 => 100644`. origin/main has 173 check.sh at 100755 and 2 at 100644 (the templates). The engine publishes a new check.sh as `mode = "100755"` (main.luau:878, :1022) and runs `chmod +x`. Every runner calls `bash <check.sh>`, so no check fails today. But the tree no longer matches main's convention, and the next publish of one of these items flips it back, which shows up as noise in later diffs.
Recommendation: restore main's modes in one mode-only commit (`git update-index --chmod=+x` on the 24; no text changes, so AC18 stays green). Optionally have AC18 also compare modes against the reference's, so a merge can't drop them unseen. Not raised in earlier rounds.

### F5 [low] `stackedOnC0120` strips `origin/` from local branch names too: a local branch named `origin/proto-c0117` is exempt by a name that isn't on the list
Where: `local name = string.match(ref, "^origin/(.+)$") or ref`. `compact.busyRefs` returns `refs/heads/origin/x` and `refs/remotes/origin/x` both as `origin/x`.
Evidence: a local `refs/heads/origin/proto-c0117` with a commit under `src/` is not listed. A local `proto-c0117` is exempt anyway, so the practical gap is small. Still, "by exact name" no longer holds, and `git diff origin/main...origin/x` resolves `refs/heads/origin/x` before the remote one.
Recommendation: have busyRefs return the full refname (or a kind beside the name), and strip `origin/` only for `refs/remotes/origin/`. Add a case: a local branch `origin/proto-c0117` is listed.

## Judged criteria (code mode only)
- JC1: pass, for the new group (the user's "Reviewed by commit group"). `git log --first-parent b99ba63c..8f0aee61` holds only the commits listed under Inputs, and groups 1 to 4 are untouched. The pinned move and core are the real groups 1 and 4 (checked above). Each commit is one kind:
  - b0b9c39 and dbb80c4: the engine's freeze only;
  - 8fc5bad: rewrite-finished's output alone (AC18 accepts it);
  - d8253e6: overrides alone, exactly the pinned patch;
  - the merges: prep only, each equal to its prep commit in c0120's folder.

  No commit mixes a move with an edit. F4's mode loss is in round 010's merge 95cc2a4, not in this group.

## Prep reference
Not recorded: F1 and F2 (medium) remain. For the round that approves:
- Prep cc6061b3's changes in c0120's folder since 56fc62dc are the ones this round reviewed or the user decided:
  - a610ff7 and ee2216b: Guess 20, its two decisions, RESTAMPED, and freeze.spec's case;
  - 13364e5 and ea33787: review 010's F1 to F4, the doc, the skill line and the lessons;
  - 43c77bd and 791b6b4: refute-010;
  - cc6061b: the widened places.
- Move f83441d629761a0da5d539a80c24f8abbca62578 and core 9b885a0875ff70bfb86a94f30cb0a4759c541ee3 are the real groups 1 and 4.
- With a stub approving review pinning all three, AC18 was green at 8f0aee61 (251) and on the tree merged with today's main d3d8f137 (252).

F1 and F2 change only the engine and freeze.spec, so the prep reference will move when they are fixed.

## Lesson candidates (for the lead)
- architecture (or tracker), new: a rule decided for one item's check doesn't belong in a general command for every caller. Scope it to the call that needs it, and give it an end condition. Check: does this exemption change the command's answer for callers the decision didn't name (other paths, after the item lands)?
- testing/seed-every-enumerated-case, an addition: when a decision covers two loops (branches and worktrees), seed the exemption in each loop. Check: does dropping the exemption from each loop turn a case red?

Verdict: changes
