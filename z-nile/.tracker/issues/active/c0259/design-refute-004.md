# Answers to design-review-004 (c0259)
Both findings are fixed.

- F1: fixed: check.sh pins only where each label sits and which issues the roadmap names; the state words are read from the delivered README and each must equal the tracker's state (the two id-less labels must say `exists`), and the error text prints the README's word. Run both ways with `real()` answering `exists` for c0117: the unchanged draft fails and the draft with c0117's row and four labels flipped passes; the round-3 mutants still fail. A Rules and mutants row and E3 record both sides, and G1's wording is corrected; consequences: a README that lags the tracker fails at delivery, so the executor must update states moved since this prep (Implementation step 1).
- F2: fixed: the legend reads "A feature's PR changes its own roadmap row and every label that names it."
