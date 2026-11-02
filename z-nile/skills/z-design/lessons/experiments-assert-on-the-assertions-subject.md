---
title: An experiment that justifies a change asserts on the same subject as the case it judges
when: design
tags: [experiments, evidence]
check: Does the experiment's question quote the exact assertion it is about (which value, which spec, which input), and would it come out differently if that assertion were still correct?
---
**Why:** c0174 design review 001 F1 (high): E3 claimed the old real-folder example no longer killed the "changed folder matches only tokens above it" mutant because c0172's `deploy.spec` names the folder. The case asserts that c0001's `ci-workflow` is selected, which only the inside-folder rule selects, so the mutant still failed it. The experiment had looked at which specs the folder selects instead of whether the asserted spec is still selected. The wrong conclusion justified a rewrite of another item's reviewed criterion and a false sentence in its document.

**How to apply:** copy the assertion into the experiment's question, run the mutant, and record the assertion's own result before deciding that a case needs changing.
