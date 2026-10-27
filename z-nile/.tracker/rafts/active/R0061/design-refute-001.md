# Refute 001: R0061 (raft mode)

Design review 001 approves; its three lows are fixed.
- F1: fixed: the Order and Whole-raft design no longer claim that c0137 running last proves anything. `./zn workstreams R0061` puts all three in wave 1; the proof is zz-execute Phase 2B step 6 (every member's check after the last merge) and RC0 (every member's check.sh on the final tree).
- F2: fixed: the Whole-raft design names both missed couplings. c0044 AC9 (not c0067 AC10) pins `add/add` and bans `<id>-<slug>` in the skills, so c0135's raft audit hint stays in engine code and never enters the Slugs bullet. c0067 AC10's banned-phrase grep also reads `engine/main.luau`, which c0135 edits.
- F3: fixed: the Theme quotes c0137's G2 ("don't widen"), and c0135's Touched list adds the two c0082 specs and `z-nile/tests/acceptance/c0135`.
