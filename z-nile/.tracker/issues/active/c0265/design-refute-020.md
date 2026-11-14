# Refutations and fixes: design-review-020
- F1: fixed: the envelope (E16, `experiments/envelope.patch`) is a run, not prose: all five spec files pass on the bare prototype and on the envelope; the cases were rewritten to per-stamp assertions, the `status` that needs a claim-free worktree runs in one, the create-only case checks its premise with a refused first beat in a worktree that runs no other command; consequences: each sibling's prep applies the patch (hand-off notes); lesson extended (bottom-layer-pins-only-what-upper-layers-keep).
- F2: fixed: lost.spec pins `35m`, `[lost 35m]` and the status order (c0030 before c0010); heartbeat.spec and beat.spec keep a 600 s old unclaimed branch; mutants M1 to M3, all killed.
- F3: fixed: the identity sentence and zz-rules' Heartbeat bullet.
- F4: fixed: `proto-c0265-raft` is pushed to origin; step 2 starts from it; the old monolith file moved out of `experiments/` to `split/` as text.
- F5: fixed (stated): one-raft delivery is enforced by the siblings' `depends_on`, which land with the pending capture after c0279, and by z-raft grouping by argument until then; the Design says so.
- F6: fixed: the user's decision "Older claims never read lost until they beat once": kind `nobeat` / `[no beat]` decided by the claim's own landing against the heartbeat module's first-add commit time (Kinds, Assumptions to veto); cases and mutants L1 to L4; c0274's hand-off carries "the takeover refuses it".
- F7: fixed: zz-rules wording for unreadable beats; AC4 label; the claim-path `ls-remote`; the two readers of "a claim"; a started raft is parked by its draft PR (stated).
- F8: fixed: a branch dated past the skew allowance no longer blocks a beat (mutant F8), an id parks only when it stands alone on both sides (mutant B1).
