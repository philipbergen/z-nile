# Refute 004 (f0265): round 4 answered

- F1: fixed: lost.spec asserts the notice and the dropped entry on the `sync` that is the old claimant's first command; the later `lessons --tags` runs assert it is not repeated and no beat of either stamp.
- F2: fixed: the stamp record is its own file, `.cache/tracker-stamp-<id>`; `tracker-claim-<id>` keeps c0116's meaning. E8: a scratch edit of `setStatus` implementing exactly this ran c0116/claims and c0053/commands-{claim,prep,start}: 37 passed, 0 failed, reverted. `Overrides: none` stands; lost.spec now also asserts the rafting taker's `release` is refused with "not this checkout's" and its own carried move passes.
- F3: fixed: the automatic beat asks the engine's own `guarded(true)` (one reader of the fence, fails closed); `autoAllowed` is deleted from the module, spec and rows; a fixture case runs a nested `lessons` with `PICKMAN_FENCE_REAL_GIT` naming the fixture's git directory spelled another way and asserts no new beat; zz-test is in Touched modules with the "Caught only by review" line as step 5.
- F4: fixed: "the gate" is removed from the long-command list; a gate run directly has no tick and the skills say to run a long gate under `./zn done`/`land` or with the loop.
- F5: fixed by the user's standing rule (real-time proofs are check.sh-only, never promoted): `dispatch.spec`, `race.spec` (now with the `--watch` and hung-remote proofs) live in `proofs/`, run once by `check.sh`; the promoted specs keep only instant cases (the bound refusal stays in beat.spec). No new decision needed.
- F6: fixed: the Design states git's relayed message, the exact `stop-restamped` texts and both parked reasons.
- F7: fixed: E5 counts, AC numbers, `heartbeat.canTakeOver`, the signature block, an unreadable `since` is unknown.
- F8: fixed: the case and AC2 say "keeps another terminal's fresh beat"; the grace itself is the pure `plan` case.
- F9: fixed: beat.spec puts the fake `gh` first on PATH.
- F10: fixed: the shim matches the push destination (`:refs/heads/main`, `:refs/zn/hb/`).
- F11: not a design defect of this issue: the c0114 `classified` failure comes from features being filed in z-nile's root on origin/main (f0263, f0265); the coordinator knows. It stays for the user's rename decision.
