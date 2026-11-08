# Refute 001 (f0265): round 1 not yet answered

Prep stopped after round 1 because the findings need the user first. Not yet fixed in the documents or specs:
- F1 (parked claims read lost): needs the user (Q5 below).
- F9 (takeover: adopt or discard the old branch, rafting claim takeover): needs the user (Q6).
- F14 (clock-skew risk weakens a guard; ZN_NOW honoured only in checks): needs the user (Q7).
- F2, F3, F4, F5, F6, F7, F8, F10, F11, F12, F15, F16, F17: accepted as written in design-review-001.md; to be fixed in the next prep pass (specs: lost.spec ordering assertions, beat.spec raft membership, done-item cases, autobeat from any ./zn command because bounded.pl caps --time at 3600, fetch before beat plus STALE grace, freshStamp for issue claims).
