# Review 009: c0262 (design mode)
Inputs: prep worktree `prep-c0262-r2` at 44b0f8a8e with its working tree (`c0262.md`: the Mutation check paragraph at line 246 and the Rules and mutants table; `check.sh`; `acceptance/*.spec.luau`; `design-review-008.md`; `design-refute-008.md`); prototype `proto-c0262-r3` at 99209a6fb (= `origin/proto-c0262-r3`, clean). The commits since round 7's 72a282566 (077b45d8c, 44b0f8a8e) each add one spend row and touch nothing else. Checked: the prep's `check.sh` and all seven `acceptance/*.spec.luau` are byte-identical (`cmp`) to 99209a6fb's, and the two folders list the same seven specs. The only write to `c0262.md` after round 7's file was written is the lead's `sed 's/M68f and M69 to M75, 42 mutants/M68f and M69 to M75, 41 mutants/'` (the lead's session record; no edit fell inside round 7's window either), and `check.sh` and `acceptance/` were last written before round 7 read them.

What holds: round 7 F1. The paragraph now says "M33, M36 to M53, M55 to M66, M61b, M68, M68f and M69 to M75, 41 mutants": 1 + 18 + 12 + 3 + 7 = 41. The table's rows checked `run` name 39 distinct ids, and the rows checked `run (M49 here)` and `run (M55 here)` add M49 and M55: 41, the same set as the list. M54 is `reasoned` and M67 appears nowhere in the document. `design-refute-007.md` F1 still says 42; it is an earlier round's record, and `design-refute-008.md` names that slip.

No findings.

Verdict: approve
