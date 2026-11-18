# Design refute 001

- F1: fixed: c0388 is taken out of the raft (`./zn unfold R0133 c0388`) and goes back to z-design for its `check.sh`; the Whole-raft design names the real interface (c0374's spec reads every member's `check.sh` once in `done/`), and the Theme and Exit criteria no longer promise `c0042/cli`; consequences: `c0042/cli` stays red on main's slow tier until c0388 is redesigned and rafted; the record is now three members, a subset of the record the review read.
- F2: fixed: RC1 and `finished-rule.luau` in the raft folder; run green on the three members and the raft, red on c0388's current `check.sh` (two hits); consequences: the script reads `tests/acceptance/c0120/rewrites.luau`, so a change to that module's interface breaks RC1 until the raft is done.
- F3: fixed: the Whole-raft design states that c0411 adds no `inputs.tsv` row for `c0043/rounds` and why that is left; consequences: none.
- F4: fixed: Cross-raft waits names R0074 (c0181), and the outside interfaces name c0325 and c0316; consequences: none.
