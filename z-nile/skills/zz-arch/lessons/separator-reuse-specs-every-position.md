---
title: A rule keyed on a reused separator is specced in every position
when: design
tags: [scanner, specs]
check: For each separator or token a scanner rule reads (`|` as a pipe and as a pattern alternative, `)` as a group end and a pattern end), is there a spec case with the judged word before it, after it and between two of them, and one where the same token appears in a position the rule must not treat as its own?
---
A one-line scanner splits at a token that the shell also uses for something else. A rule keyed on the token's meaning in one position breaks, or is fooled, in the other.

**Why:** c0231 design review 001 F1: `split` cut a case pattern `yes|y)` at the `|` like a pipe, so the new `yes` rule refused a pattern the spec said passes; the spec only had `y|yes)` (yes last), and `(yes)` inside a case body passed as if it were a pattern.

**How to apply:** list the positions of each token (first, middle, last, nested in a here-document, inside a case body) and give each a pass or refuse case before the review.
