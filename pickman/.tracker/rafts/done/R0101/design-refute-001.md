# Refute 001: R0101 (raft mode)

- F1: fixed: the Theme now copies both decisions from game-design.md word for word (c0176's Levels rule and c0177's Slower-ghosts row), each checked with `git grep -F`; the invented sentence is gone; consequences: none (no member's design quoted it).
- F2: fixed: check.sh gains RC1 (`git diff --quiet origin/main...HEAD` over pickman's `src`, the two Rojo projects, `scripts` and `.tracker/architecture.md`), Exit criteria names it and Risks says an emergent issue that needs a game file means stop and escalate; consequences: an emergent fix to a game file can no longer ride this raft, which is intended and stated; RC1 passes on the rafting branch today.
- F3: fixed: "step 0" is "step 1" in both places, and the Whole-raft design names both things c0177's prep landed outside its patch (the game-design.md sentence and the reworded labels of `done/f0125/check.sh`); consequences: none.
- F4: fixed: Cross-raft waits lists R0095, c0196, c0182 and R0066 with the `depends_on` each waits through; consequences: none (R0094 and R0095 already state these waits on their side, so no other raft document changes).
