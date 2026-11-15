# Answers to design review 001 (R0097)

The review read the record `[c0123@d08f1e683355, c0189@92eb2ee3fbdd]`. Asked what to do with members that cannot be stacked as designed, the user answered (2026-11-15): "Redesign as stacks (Recommended)". Both members are unfolded and go back to z-design, to be redesigned as two layers of one raft; the raft is released with no member.

- F1: fixed: c0189 and c0123 are unfolded on the user's ruling; the redesign has c0189 ship `#!/bin/sh -p` with the matching pin and c0123 drop its override of c0189's `wiring.spec` and its first-line edit; consequences: both approvals are lost and each needs the user's approval again; folding them again is a new record and a new coherence review.
- F2: fixed: c0123 is unfolded; its redesign drops `tests/acceptance/c0189/wiring.spec.luau` from its `check.sh` AC6, since c0189's own check runs that spec; consequences: none beyond F1's.
- F3: fixed: c0123 is unfolded; its redesign pins its zz-arch rule without the number, because c0193 (active in R0072) pins rule 9 with other text; consequences: the redesign must also read the `z-nile/lib/` row both members edit.
- F4: fixed: with c0189 out of the raft no grouped hash goes stale when R0070 lands; the redesign is rafted only after R0070 is done, as c0189's design says; consequences: none.
- F5: fixed: the redesign of the pair runs both members' whole acceptance sets on one tree with both prototypes applied in raft order, before it is rafted (lesson z-raft/run-sequestered-specs-on-all-prototypes-together); consequences: none.
- F6: fixed: recorded for the redesign: R0068's c0122 (active) edits the same zz-test Ref guard line, `fence.sh` header and `repo-fence.spec` allow-list as c0123; consequences: none.
- F7: fixed: the four statements carried from c0123's former raft leave with the members; the raft document that regroups them is written fresh (lesson z-raft/copied-raft-text-is-reverified); consequences: none.
