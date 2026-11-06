# Answers to design-review-005 (c0259)
Both findings are fixed.

- F1: fixed: the label scan covers the whole section (the intro and the Roadmap prose included); table rows are read by their issue column; the legend line is the only exempt text and is pinned word for word in `legend.txt`; mutants: a labelled sentence added to the Roadmap prose, to the intro and to the legend line each fail AC7 (run); the earlier mutants and both directions (the draft against a tracker where c0117 is done fails; the flipped draft passes) still hold; consequences: none new.
- F2: fixed: the lesson's "How to apply" is one clause per rule, and its `check:` carries F1's question.
