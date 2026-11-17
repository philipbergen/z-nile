---
title: An escaping case repeats every character it escapes
when: both
tags: [specs, mutants, escaping]
check: Does every hostile input in a case that pins an escaper or rewriter hold each special character it handles at least twice, side by side, in every field the code escapes, and is there a mutant row for "only the first occurrence is replaced"?
---
An escaper that replaces only the first match of each character (a `gsub` with a count, a `find`/`sub` loop that stops after one) passes every input in which each special character appears once. A case built from single occurrences pins "this character is escaped", not "every occurrence is".

**Why:** f0395 design review 001 F1: the rich-text escaping case used `"A<B>&C"`, `"<5 & 6>"`, `"&1"`, `"S>"` and `"<r&>"`, and a `plain` whose three `gsub`s each stopped after one replacement passed all nine cases.

**How to apply:** write the hostile inputs with each special character doubled and adjacent (`"A<<B>>&&C"`, `"<<5 && 6>>"`), in every field the code escapes, keep an order-sensitive pair (`&&<<`) so "`&` first" stays observable, and add the mutant "each replacement limited to one" to the Rules and mutants table.
