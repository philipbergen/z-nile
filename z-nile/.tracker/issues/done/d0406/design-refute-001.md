# Design refute 001

- F1: fixed: AC7's one check line now runs `rounds.spec` and `retired.spec` together; G5 replaces the second half of G4 and states the three measured times; consequences: the check costs two to five minutes more at each finish, restack and done of this one-layer raft, stated beside the line. c0411's design can now quote this line.
- F2: fixed: `experiments/E2-mutants.sh` clones the checkout into `.cache/d0406-mut`, refuses to go on unless it is inside that clone, applies `prototype.patch` there and removes the clone; the document says to run it under `./zn run --time 1500`; consequences: none (the results were rerun this way, twelve mutants).
- F3: fixed: the board case asserts the page has no "does not parse", the summary case asserts `spend.readTotals` over the typed `spend.md` (2 records, 6.5 minutes, 11 tokens), and M2 (ledger unchanged) now fails both; the Design's Siblings names `board.luau` 275 and `spend.readTotals`; consequences: none.
- F4: fixed: d0020 gains an `alpha` row and a `zeta` row with no tokens; the case asserts `alpha` before `mystery` and no `zeta` line; mutants M10 and M11, two Rules rows; consequences: none.
- F5: fixed: the affected gate was run on the prototype and its result is E5; consequences: none.
- F6: fixed: `metrics <id>` appends an unlisted phase to its stage order, sorted (G6, a fifth edit in `prototype.patch`); the stages case asserts d0020's `alpha`, `mystery`, `zeta` lines in that order; mutants M9 and M12; consequences: a stage line appears for a phase with rows whatever its tokens, as for every listed stage.
