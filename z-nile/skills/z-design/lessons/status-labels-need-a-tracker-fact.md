---
title: A status label is checked against the tracker
when: design
tags: [docs, stale-text]
check: Does a document that labels features (exists, designed, planned) define each word by a tracker fact, carry a label in every section, and have a check.sh line that fails when a row or a labelled sentence differs from the item's real state, in either direction? If only the id inside a label changes, or a label moves to another sentence, does the check fail; and if the tracker moves one named issue a step and the README follows it, does the check pass; and if a labelled claim is added where the section has no labels today (its intro, the prose under a table), does the check see it; and for each sentence labelled `exists`, which file or command proves it, and was it read or run?
---
A README that says what is built and what is only wanted is read as the truth. Labels written by hand drift, and a shape check alone passes a row marked `exists` for work that is only captured.

**Why:** c0259 design review 001 F1, F2: the draft had five state words for a three-word legend, a Trust section with no label that described unbuilt guards in the present tense, and three mutants (all labels stripped, six rows marked `exists`, Trust rewritten as built) all passed the first specs.

c0259 design review 003 F1: a check that parsed the label and its id from the text passed five mutants (a borrowed done issue's id, a label moved to another section, a row whose first id sat in another column).

c0259 design review 004 F1: the pinned map also pinned each state, so no README could pass once any named issue changed state, and the experiments only tried mutants that should be refused.

c0259 design review 005 F1: the scan skipped the Roadmap sub-section and the intro, so two false labelled sentences added there passed; the scan now covers the whole section and exempts only the legend line, pinned word for word.

R0085 review 001 F1: check.sh pinned the labels, not the claims under them; a sentence labelled `exists` ("everything you produce lands by pull request") was false, since captures and claims are pushed without one.

**How to apply:** define each state by a tracker fact (done, `design: ready`, draft), name the issue in every label, pin which issue each label belongs to by its position in the reviewed text (an ordered list in check.sh) pin only what the executor may not change, read the state words from the delivered file and judge them against the tracker, scan every part of the section where a label could appear (exempt only text pinned word for word), and run the check on a README that follows a simulated tracker change, put the exact vocabulary and the truth check in check.sh (which reads the live tracker), and keep only the shape (every section labelled, every row ends in a defined state) in the promoted spec.

c0264 design review 001 F1: a part of a document that carries no labels and no checked words (a diagram) escapes both the label truth check and the vocabulary check; give it a check of its own (the words it must show), or an outcome that names it ("the diagram gains the new tickets") stays unchecked.

c0264 design review 002 F1: for a diagram, check the edges that carry the rule, with fixed node ids, not only its words: words floated into a node pass a word check while the flow they name is gone.
