# Review 002: R0096 (final mode)
Inputs: R0096/1/d0298 at 999db0ce5 (finish commit 9fe4b132f, stacked on origin/main ed4fadfa3, which did not move during this review); final-review-001.md and final-refute-001.md; `git diff 8d6ff5974 HEAD` (round 1's head, still reachable); d0298.md lines 459 to 475 (Implementation step 5, the Verification log's two new entries), results.txt, harvest.md, trace.md. This round judges only the answers to round 1 and what changed since; it does not repeat round 1's review.
Runs (this reviewer, on 999db0ce5): `./zn sync --fetch` (synced to ed4fadfa3). `./zn trace R0096 --check` prints `ok: R0096`. `./zn approve d0298 --check` holds (approved 51d6c5c6..., 2026-11-19T06:12:07Z). `./zn lessons --uncovered R0096` (every finding is covered) and `./zn lessons --check` pass. No spec was run again: no code changed.
Code since round 1: `git diff 8d6ff5974 HEAD` outside `.tracker/` lists one file, `z-nile/skills/z-raft/lessons/escalations-are-bullets.md` (2 lines), which is main's own commit under the rebase. No engine file, spec, `check.sh` or skill of this layer differs from what round 1 read. Sequestration is as round 1 found it: only `A .../d0298/acceptance/watch.txt`.

## The answers to round 1

- F1 (fixed): true and sufficient. The merge base of HEAD and origin/main is origin/main (ed4fadfa3), `Commit:` names 9fe4b132f, which is the layer's finish commit and the commit that last wrote `results.txt`, and the trace check passes. No finding of lesson zz-review/not-stacked-is-main-moving applies now.
- F2 (fixed): true and sufficient. The new entry lists the runs in order, says "names not kept" for the 5 and the 17, keeps the first error of the `c0119/capture-cli` red, and says that load is likely and not proven. Its last counts equal the committed `results.txt`, counted here: 177 spec files, 1098 cases. Its other counts agree with each other and with round 1: the slow tier totals 913 in all three runs it names (912 and 1, 908 and 5, 904 and 9), the first finish's 1044 and 170 are the figures the older entry already had, and the reds are the ones reported to round 1 (the capture-cli push that could not write an object file; the 5 and 17). The kept outputs themselves are session files this review cannot read, so the nine-case count and the load figures rest on the author's word; nothing committed contradicts them. `./zn approve d0298 --check` holds after the edit, as the answer says.
- F3 (fixed): true, and the answer is better than round 1's recommendation. Round 1 said the Test plan is outside the approved contract; it is inside (`z-nile/engine/contract.luau:26`, `contract.HEADS` names Problem, Solution, Design, Acceptance criteria, Test plan), so editing lines 398 to 406 would have voided the approval. The author corrected only Implementation step 5 (outside the contract, one line changed in place) and named the other three, and the raft's Theme, in the log with what is true. That mistake was this review's own in round 1; it cost nothing because the author checked before editing. Step 5 now lists three files and still says "a change to either": wording only, no check reads it.

## Trace
`trace.md` is unchanged by this round. The edits since round 1 changed d0298.md line 464 in place and appended two lines after 473; the highest line the table cites is 468 (the user's ruling on parallel-runner, still there). No code file changed, so no code or spec line moved. `./zn trace R0096 --check`: `ok: R0096`.

## Judged criteria
- None: d0298 has no Judged criterion.

Verdict: approve
