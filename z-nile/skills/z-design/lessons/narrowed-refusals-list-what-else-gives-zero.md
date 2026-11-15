---
title: A narrowed refusal lists every other input that gives the same empty result
when: design
tags: [refusals, scope, edge-cases]
check: When the design deletes or narrows a refusal, does the new condition match the captured rule exactly (for example "only the template or nothing") rather than stopping the refusal for every input that gives zero results, and has every other such input (a leading decision line, a fenced block, a comment) a case?
---
A refusal written as "the result is empty" is wider than the rule the capture states ("the section holds only the template"). Removing it for the empty result lets every other input that yields nothing through without a word.

**Why:** c0330 design review 001 F2: the first design deleted the "missing captured ## Solution" refusal for any Solution with no outcome. A Solution that opens with a `Decided with the user` line also yields no outcome (the reader stops at that line), so the user's decided approach would never be traced, and a fence-only Solution vanished too. The reader for the Problem had already been given a second read for the same shape; the Solution had not.

**How to apply:** state the narrowed condition in the capture's words, enumerate the inputs that give an empty result, and pin each with a spec case. When one section gets a fallback, give every section read the same way the same fallback or say why not.
