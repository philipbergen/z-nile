# Review 013: c0120 (code mode; re-pin after the landing's prep changes)
Inputs: `git diff 0ac9b8bb e8a34f3e -- z-nile/.tracker/issues/c0120 z-nile/.tracker/rafts` (prep-c0120 at e8a34f3e, squash-merged to main as #99 = 5469d873, tree equal to e8a34f3e); `origin/impl2-c0120` 1cf6ad92..513fa287 (merges 1f41df64 and 8e223e28 of prep, then 513fa287, the freeze's move rule). I read review-012 first. Every run was in scratch clones under `code-review-c0120b-010/`, with a bare mirror of GitHub as `origin`. The real repository was only read.
Dropped from review-012: none (it had no findings).

## What was checked
- **The prep delta changes c0120 only as described.** The non-c0120 paths in 0ac9b8bb..e8a34f3e (d0124, R0044, c0121, c0138, `next`) arrive with the merge of origin/main 5eada2e5, and in impl2 each one is byte-equal to main's, under pickman/ for the pickman items. c0120's folder gains `raft: R0048`, `design: ready`, a status stamp, review-012 (equal to the approved round), Rules row V50, a Verification-log bullet, and the two acceptance edits. Nothing else changes. At 8e223e28, every file in c0120's folder equals e8a34f3e (55 files). 513fa287 then adds two Guess 20 bullets to c0120.md. That file isn't sequestered.
- **The two fixes only widen the search.**
  - `finished.luau`: `OWN` is the first existing folder of backlog, then `active/`, then `done/`, with `done/` as the fallback. Before the fix it was backlog, else `done/`. The two differ only when the backlog folder is gone and `active/` holds c0120, the case that used to refuse.
  - The patches loop reads `ownBase:<dir><name>` across the same three folders and stops at the first hit. At the pinned prep only the backlog copy exists, so the same patch is read.
  - `finished.spec`'s `ownScript` tries backlog, then `active/`, then promoted, so the three old two-way lookups gain `active/` and nothing else.
  - No comparison, rewrite or verdict logic changed.
- **V50 is killed.** With `active/` removed from `OWN_DIRS`, finished.spec gives 5 passed, 1 failed. The failure is at the new `ready` step (`expectGreen`, finished.spec:321, called at :334). The unmutated spec is green through AC11.
- **Simulated ready, done faithfully.**
  - Mirror main = 5469d873, the real squash of #99. The real `./zn ready R0048` against the mirror gives commit 68b1098: 57 renames into `active/`, with only the two status lines changed and no `check.sh` rewritten.
  - Then a branch `R0048-pickman-home` from origin/impl2-c0120, merged with that main. Its 55 conflicts were resolved to main's side (F1). The merge against the impl tip is exactly the ready commit, and there is no `mode change` against main.
  - Then 513fa287 merged in, and this review (pins below) put at `active/c0120/review-013.md` and committed.
  - `./zn sync --fetch`, then `./zn check c0120`: **18/18**. AC18 and AC16 are green.
  - Before 513fa287, the same tree was 17/18. AC16 listed proto-c0121, and the impl-c01xx/proto branches were no longer exempt once #99's squash put the prep's content on main. 513fa287 fixes that.
- **513fa287 (the coordinator's addition).**
  - It adds exactly two things:
    - three exact keys in `APPROVED_FOR_C0120` (prep-c0121, proto-c0121, impl-c0120);
    - one check in `stackedOnC0120`: the move pinned by the highest-numbered approving review-NNN.md in c0120's folder (backlog, `active/` or `done/`) is an ancestor of the ref.
  - Nothing else in the function, `c0120FreezeOn` or busy changed, and the freeze-only and old-layout gates still apply.
  - In the simulation the move rule exempts exactly `git branch -r --contains f83441d6`: impl-c0115 to c0118, impl-c0121, impl2-c0120, proto-c0115 and proto-c0116.
  - Look-alikes still block. Local branches proto-c0121-x, prep-c0121b, xprep-c0121, impl-c01200 and a local `origin/impl-c0120` were each listed as `branch … changes`, while the real `origin/impl-c0120` was "approved by name".
  - busy-holds-move.spec and freeze.spec give 9 passed. V51 (the move rule dropped) and a second mutant (the `Verdict: approve` test dropped) each turn busy-holds-move.spec red.
- **Repository safety.** None of the changes touches a fence file. `c0120Move` only reads files and runs `merge-base --is-ancestor`. The new spec's fixture is under `.cache/busy-holds-move` (trackerfix).

### F1 [low] Merging the squashed #99 into the raft branch conflicts on all 55 paths of c0120's folder and R0048
Where: the landing's merge of origin/main (after `ready`) into the raft branch.
Evidence: #99 was squash-merged, so the merge base of impl2-c0120 and main is 5eada2e5, and both sides changed c0120's folder and R0048 from it. Rename detection fails, which leaves add/add (`AA`) entries under `active/c0120/`, unmerged backlog paths, and a modify/delete on `rafts/R0048/check.sh`. The contents are identical on both sides. A `git add -A` resolution keeps both copies: the backlog folder and the `active/` one.
Critique: the resolution is mechanical, but the obvious shortcut is the wrong one.
Consequences: none beyond the resolution.
Recommendation: for every unmerged path, take main's version where main has the path, and delete it otherwise. Then check that `git diff origin/impl2-c0120 HEAD --stat` is exactly the ready commit (57 files, 2 lines changed) and that `z-nile/.tracker/issues/c0120` and `rafts/R0048` are gone.

### F2 [low] AC16 is green only on a branch named `R0048-…`
Where: `cmd.busy` (`own = string.match(current, "^(R%d%d%d%d)%-")`).
Evidence: in the readied simulation on a branch named like `impl2-c0120`, `./zn busy tracker src tests` prints `raft R0048 is active` and exits 1. On `R0048-pickman-home` it doesn't.
Critique: PR #107's head is `impl2-c0120`, so running `./zn check c0120` or `./zn done R0048` there turns AC16 red. This is the tracker's existing rule (one raft, one branch `R0010-<slug>`) and needs no code change.
Consequences: none.
Recommendation: land from a branch named `R0048-pickman-home`, created at impl2-c0120's tip, and point #107 at it, or open the raft's PR from it.

### F3 [low] busy-holds-move.spec's look-alike case doesn't resemble the three new names
Where: `z-nile/tests/tooling/busy-holds-move.spec.luau` (the look-alike is `impl-c0199`).
Evidence: the exact-match table makes look-alikes block, and I confirmed that by hand (above). freeze.spec's V34 and V35 pin the mechanism for the older names. No case pins `proto-c0121-x` or a local `origin/proto-c0121` specifically.
Critique: low, because the lookup is shared with the names that are already pinned.
Consequences: none.
Recommendation: optionally list a `prep-c0121-x` branch in the existing case.

## Judged criteria (code mode only)
- JC1: pass. The new commits are one kind each:
  - 1f41df64 and 8e223e28 are prep merges whose c0120 folder equals the prep;
  - 513fa287 is the freeze rule, its spec and its Guess 20 record.
  Groups 1 to 4 are untouched, and the move and core pins are as review 012 verified.

## Prep reference
Prep reference: e8a34f3e9c09b017c9c65f5447117d30cc012b8f
Move commit: f83441d629761a0da5d539a80c24f8abbca62578
Core commit: 9b885a0875ff70bfb86a94f30cb0a4759c541ee3

Verdict: approve
