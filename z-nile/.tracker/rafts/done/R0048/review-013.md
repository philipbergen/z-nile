# Review 013: c0120 (code mode; re-pin after the landing's prep changes)
Inputs: `git diff 0ac9b8bb e8a34f3e -- z-nile/.tracker/issues/c0120 z-nile/.tracker/rafts` (prep-c0120 at e8a34f3e, squash-merged to main as #99 = 5469d873, tree equal to e8a34f3e); `origin/impl2-c0120` 1cf6ad92..ee560e40: prep merges 1f41df64 and 8e223e28, then 513fa287 (the freeze's move rule and three names), 78211baf (the merge of origin/main d236873c, the real ready of R0048), b9e1de29 (a rename) and ee560e40 (c0120's own raft). I read review-012 first. Every run was in scratch clones under `code-review-c0120b-010/`, with bare mirrors of GitHub as `origin`. The real repository was only read.
Dropped from review-012: none (it had no findings).

## What was checked
- **The prep delta changes c0120 only as described.** The non-c0120 paths in 0ac9b8bb..e8a34f3e (d0124, R0044, c0121, c0138, `next`) arrive with the merge of origin/main 5eada2e5, and in impl2 each one is byte-equal to main's, under pickman/ for the pickman items. c0120's folder gains `raft: R0048`, `design: ready`, a status stamp, review-012 (equal to the approved round), Rules row V50, a Verification-log bullet, and the two acceptance edits. Nothing else changes. At 8e223e28, every file in c0120's folder equals e8a34f3e (55 files).
- **The two fixes only widen the search.**
  - `finished.luau`: `OWN` is the first existing folder of backlog, then `active/`, then `done/`, with `done/` as the fallback. Before the fix it was backlog, else `done/`. The two differ only when the backlog folder is gone and `active/` holds c0120, the case that used to refuse.
  - The patches loop reads `ownBase:<dir><name>` across the same three folders and stops at the first hit. At the pinned prep only the backlog copy exists, so the same patch is read.
  - `finished.spec`'s `ownScript` tries backlog, then `active/`, then promoted, so the three old two-way lookups gain `active/` and nothing else.
  - No comparison, rewrite or verdict logic changed.
- **V50 is killed.** With `active/` removed from `OWN_DIRS`, finished.spec gives 5 passed, 1 failed. The failure is at the new `ready` step (`expectGreen`, finished.spec:321, called at :334).
- **The ready merge (78211baf) is right.**
  - At ee560e40, `active/c0120` and `active/R0048` equal origin/main d236873c, except for c0120.md's three Guess 20 bullets (513fa287, ee560e40).
  - No backlog copy of either is left.
  - There is no `mode change` against main.
  - All sequestered files in c0120's folder are R100 renames.
  - When I merged the squashed main by hand, git raised 55 add/add and modify/delete conflicts, all with identical content. 78211baf resolved them to main's side, as it should.
- **513fa287 (the move rule and three names).**
  - It adds exactly two things:
    - three exact keys in `APPROVED_FOR_C0120` (prep-c0121, proto-c0121, impl-c0120);
    - one check in `stackedOnC0120`: the move pinned by the highest-numbered approving review-NNN.md in c0120's folder (backlog, `active/` or `done/`) is an ancestor of the ref.
  - The freeze-only and old-layout gates still apply.
  - It exempts exactly `git branch -r --contains f83441d6`: impl-c0115 to c0118, impl-c0121, impl2-c0120, proto-c0115 and proto-c0116.
  - Look-alikes still block. Local branches proto-c0121-x, prep-c0121b, xprep-c0121, impl-c01200 and a local `origin/impl-c0120` were each listed as `branch … changes`, while the real `origin/impl-c0120` was "approved by name".
  - V51 (the move rule dropped) is killed, and so is a second mutant I tried (the `Verdict: approve` test dropped).
- **b9e1de29** renames `move` to `pinned` in five lines, and changes nothing else.
- **ee560e40 (c0120's own raft).**
  - An active raft is uncounted, and named on stderr, only while the freeze is on and only when its document on origin/main has `issues: [...]` containing exactly `c0120`, compared as a comma-delimited token.
  - The spec covers three cases:
    - R0048 is ignored;
    - R0049 with `[c0120x, c0121]` is listed;
    - `busy` without paths lists R0048.
  - V52 (as given) is killed. I also ran two mutants of my own, and the spec kills both:
    - the `freeze and` gate dropped: red;
    - a plain substring match for `c0120`: red.
  - Only c0120's raft can list c0120, because `ready` refuses a raft whose list and members disagree.
- **Pin check on ee560e40.** I ran it in a clone of a mirror of GitHub (main = d236873c, the real ready, with R0048 and c0120 in `active/`), on the branch `impl2-c0120`, with this review at `active/c0120/review-013.md`.
  - `./zn sync --fetch`, then `./zn busy tracker src tests`: exit 0. The output names `raft R0048 (c0120's own)` and the exempt branches on stderr.
  - `./zn check c0120`: **18/18**, with AC16 and AC18 green.
  - busy-holds-move.spec gives 2 passed.
- **Repository safety.** None of the changes touches a fence file. The new engine code only reads files and runs read-only git (`merge-base --is-ancestor`, `show`). The spec's fixture is under `.cache/busy-holds-move` (trackerfix).

### F1 [low] busy-holds-move.spec has no look-alike of the three newly approved names
Where: `z-nile/tests/tooling/busy-holds-move.spec.luau` (its branch look-alike is `impl-c0199`).
Evidence: the exact-match table makes look-alikes block, and I confirmed that by hand (above). freeze.spec's V34 and V35 pin the mechanism for the older names. No case pins `proto-c0121-x` or a local `origin/proto-c0121` specifically.
Critique: low, because the lookup is shared with the names that are already pinned.
Consequences: none.
Recommendation: optionally add a `prep-c0121-x` branch to the existing case, expected to be listed.

## Judged criteria (code mode only)
- JC1: pass. The new commits are one kind each:
  - 1f41df64, 8e223e28 and 78211baf are merges, of prep or of main by the layout rule, that change nothing else;
  - 513fa287 and ee560e40 are each one freeze rule, with its spec case and its Guess 20 record;
  - b9e1de29 is a rename.
  Groups 1 to 4 are untouched, and the move and core pins are as review 012 verified.

## Prep reference
Prep reference: e8a34f3e9c09b017c9c65f5447117d30cc012b8f
Move commit: f83441d629761a0da5d539a80c24f8abbca62578
Core commit: 9b885a0875ff70bfb86a94f30cb0a4759c541ee3

Verdict: approve
