---
title: Each fail-closed rule has an input only that rule turns to the safe answer
when: design
tags: [specs, fail-closed, mutants]
check: For a function made of several fail-closed rules, does every rule have a case whose input trips only that rule (every other rule says "narrow"), so dropping that one rule turns a case red?
---
When two rules both answer "run everything", an input that trips both proves neither. Dropping one of them leaves the suite green.

**Why:** c0239 design review 004 F2: every "outside the home" path in stop.spec (`scripts/other.sh`, `zn`) already forced a full run through rule 1, so rule 4 could be deleted and all six cases still passed. Four cases (`SETUP.md`, `z-nile/tests/notes.md`, a z-nile tracker path, and the project's own tracker root as the allowed counterpart) kill it.

**How to apply:** list the rules, and for each pick an input that passes all the others; run the rule-dropped mutant.
