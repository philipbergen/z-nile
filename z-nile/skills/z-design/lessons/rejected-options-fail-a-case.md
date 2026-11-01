---
title: A user's choice fails a case when the rejected option is built
when: design
tags: [decisions, acceptance]
check: For every `Decided with the user` line, does some spec case fail when the option the user turned down is implemented, rather than only a docs text match on the decision's words?
---
A decision recorded only as text in game-design.md (or the issue) pins the words, not the behaviour: an executor who builds the option the user rejected passes every check.

**Why:** f0147 design review 004 F2: the user chose "Keep it, record it" for the idle longer-jumps boon; only docs.spec matched the sentence, and a mutant that re-rolls the boon (the turned-down option) passed both f0147's and f0126's specs.

**How to apply:** for each decision, write the case from the rejected option's point of view (here: with long hops on, some seed still rolls longer jumps and nothing else is granted), and add its mutant row.
