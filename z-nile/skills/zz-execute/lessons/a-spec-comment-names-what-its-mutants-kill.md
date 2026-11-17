---
title: Each thing a spec's comment says it pins has a mutant that spec kills
when: build
tags: [specs, mutants, review]
check: For each tolerance, input or rule a new spec's comment says its sample exercises, does the cheapest mutant of it fail that spec (not only the item's unit spec)?
---
A spec written to answer a review often carries a comment listing what its sample covers. A sample built by hand can place an input where an earlier step removes it (a character at the end of a text that is trimmed), so the comment claims a rule the spec never sees, and a mutant of that rule leaves it green.

**Why:** R0068 final-review-001 F1: `pin-rule.spec` said its sample keeps a form feed inside a line, but the form feed was the text's last character and the rule's outer trim removed it; a mutant collapsing or breaking on a form feed passed the spec.

**How to apply:** for each item the comment names, run one mutant of the code it tests against the new spec alone, and keep the item in the comment only when that spec fails.
