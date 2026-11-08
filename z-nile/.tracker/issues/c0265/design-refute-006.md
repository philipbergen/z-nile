# Refute 006 (c0265): round 6 answered (the user: "one more" round, then this one)

- F1: fixed: the rafting-takeover case no longer runs `sync` in `wt`; the old-claimant case's first `sync` asserts the one-time notice for both c0010 and the rafting claim, then the rafting claimant's carried move is refused in the same case. Consequence: the notice assertions now sit on exactly one command per entry.
- F2: fixed: the board reads the verdicts (`board.build(root, checkout, verdicts?)`, badges `lost 45m` / `parked` / `stale?`, lost first in its bucket, unreadable: no badges and a note); `board.luau` is in Touched modules; lost.spec has a board case; the rule has a Rules row. Consequence: the board gains a network read only through `cmd.board`; `board.build` without verdicts is unchanged, so existing board specs are unaffected.
- F3: fixed: the takeover's claim commit subject is `tracker: <id> preparing (takes over <old stamp>)`; lost.spec asserts it for an issue and a raft, so an implementation that records nothing fails.
- F4: fixed: the Design states that the stamp-record check precedes the member design check; the old-rafting-claimant case relies on it by name.
- F5: fixed: E8 re-run with the record also written by `rememberClaim` (so `new raft`, `fold`, `unfold`, `recombine`): c0116/*, c0053/*, ready-members, recombine-members: 139 passed, 0 failed, 18 files, reverted. The first beat is an additive ref push and changes no tracker state.
- F6: fixed: the row's mutant is now "a fence list replaced instead of appended".
- F7: fixed: an instant case (`lsfail`, `lessons --tags` twice) guards the failed-attempt throttle in the promoted lost.spec; check.sh runs the proofs only while the item's `acceptance/` folder exists (before `done`).
- F8: fixed in part: the duplicated setup case in race.spec is removed; the unused fixture parts stay (harmless, removing them risks the shim arms the other cases use).
- F9: fixed: Test plan, AC3/AC5/AC6 labels (copied word for word into the document), Rules rows (record only by `setStatus`; `unfold`), AC6 greps SETUP.md (NTP) and the zz-test line, the lessons' Why lines now say c0265.
- F10: fixed: the Design states that the explicit `beat` and the dispatcher's child refuse in a guarded checkout.
