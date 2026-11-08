# Refute 005 (f0265): round 5 (final) answered

Round 5 is the final round and it holds two highs, so per z-design the issue goes to the user whatever is answered here; all of it is fixed in the documents and specs.
- F1: fixed: beat.spec's nested case uses the fence's own spelling (`rev-parse --path-format=absolute --git-common-dir`), appends to the inherited `PICKMAN_FENCE_REAL_GIT`, and asserts the entry file is byte-identical (a refused push still advances an epoch, so a mutant fails on either platform).
- F2: fixed: the stamp record is written by every claim path, `new raft`, `fold`, `unfold` and `recombine` included (and each gives a first beat); lost.spec asserts the old rafting claimant (who ran `new raft`) is refused its carried `status <R-id> prepared` after the takeover.
- F3: fixed: the instant cases (takeover race, fold's beat) are back in the promoted `acceptance/edge.spec.luau`, run under AC3; `proofs/race.spec.luau` keeps only what waits; the no-retry-inside-the-interval case stays in the proofs because it waits on a real kill.
- F4: fixed: the Design fixes the call form (`git <subcommand> …` from the checkout's directory, never `git -C`).
- F5: fixed: z-design, z-raft and z-run each say to take `./zn lost` first, and AC6 greps all three.
- F6: fixed: the document's ACs are copied word for word from check.sh, the Test plan and the rows point at the right specs, `heartbeat.setting` is in the signature block, the inclusive case is renamed (the revive case pins the edge).
- F7: fixed: `Claim.since` is optional; with no beat and no `since`, the kind is `unknown` (shown `[stale?]`, never lost); pure case and mutant run.
