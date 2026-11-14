# Refute 002: c0276
- F1: fixed: the band head draws its raft's mark (`board.html`), `board.spec` seeds a rafting claim (R0020, stamp on the raft only) and a plain raft, `verdicts.spec` asserts the mark inside the band head; the decision that bands are marked, not moved, is stated in section 1 and Usability (the capture's "lost work first within its bucket" read as the cards of a bucket or band; named in the report to the user); Rules rows and mutants N9, N10 (run); consequences: a rafting claim in the fixture follows the layer rule like the issue claims (its beat is force-pushed last, no command runs in a worktree holding it)
- F2: fixed: step 6 now says to leave `serve.luau` alone, E6 says "not run, and not claimed", `size` is 170 (the measured diff, no wiring); consequences: Q1 stays the user's
- F3: fixed: cases for `PICKMAN_PUBLISH=0` (nothing read, nothing said) and an unreadable registry (one warning); Rules rows and mutants N18, N22 (run); consequences: shim switch `noregistry`
- F4: fixed: E4 states what was run (46 files, plus the 39 more the reviewer ran: 311 passed) and that the whole suite end to end is the merge's `--full`; consequences: none
- F5: fixed: check.sh labels are generated from the document's ACs and AC3 says fixtures are unguarded; consequences: none
- F6: fixed: the page case has c0030 lost in the same band as c0010 and c0020, asserts c0030 before c0010 before c0020, and the stale card is checked in the list; Rules row and mutant N21 (run); consequences: none
- F7: fixed: sections 1 and 3 state `board.Verdict` and both registry texts, the zz-rules row says a rebuild skips the fetch of main; the extra space on cards stays (c0118's page strings pass) and is named; consequences: none
- F8: fixed: c0284 is in section 4's table; consequences: none
- F9: fixed: Scalability states the measured real-repository cost (0.6 to 0.7 s and 0.5 s) and the fixture cost; consequences: none
