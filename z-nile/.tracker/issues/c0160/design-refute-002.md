# Refute 002: c0160 (design mode)

Verdict approve; both lows answered, no round 003.

- F1: fixed: main merged into the prep; E4 cites c0141's landed fix, 2bd65f50 (#164, raft R0062: `uses-module.spec` builds its needle from parts), and the stated base is the merged main; the prototype re-ran with c0141's fixed specs promoted: architecture.spec passes. The merge also brought a refined capture of c0160 on main: its Non-goals are kept beside the design's, and its outcomes (backlog and active items, a glob that matches and one that doesn't) are added to the spec's first case and to AC1's text. Consequences: case 1 and later counts grow by the active item (spec 6/6).
- F2: fixed: the Solution and Design item 2 say the scan takes the scanned checkout's registry while a reader called without homes (`rewrites.rewrite`'s call) takes the running checkout's, the same two homes for every caller today; the prototype carries a one-line comment at that call (`experiments/c0160-on-c0141.patch`). Consequences: none.
