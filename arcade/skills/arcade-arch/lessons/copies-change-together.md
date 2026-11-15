---
title: A copied feature changes in both homes until the switch
when: design
tags: [arcade, copy-then-switch, overrides]
check: While a feature lives in both the game and the library (after the arcade copy, before the game's switch), does the design say that a change to either copy is made to both and that the switch diffs them before deleting the game's? And does the cost it gives for the next game or place include the promoted specs that pin today's list (an `Overrides:` line and its chore)?
---
The arcade plan moves a feature by copying it and its specs, then switching the game and deleting the old copy. Between the two, the copied acceptance spec runs on the library's copy only, so a fix made to the game's copy turns nothing red and is lost at the switch. Likewise, a promoted spec that pins a list (the five places) is red the day a sixth entry lands.

**Why:** f0199 design review 001 F3: the Maintainability section said "AC1 keeps the two copies equal" (it only judged arcade's copy) and called a sixth place "one data row", missing a record field and the override of f0199's promoted places spec.

**How to apply:** in a copy issue, state the rule for the window (change both; the switch's design diffs the copies) under the Interfaces the switch relies on, and price the next entry with its override.
