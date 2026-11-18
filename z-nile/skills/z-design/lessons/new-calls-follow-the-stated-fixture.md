---
title: Every call a prep writes follows the fixture rule its own design states
when: design
tags: [fixtures, specs, cross-item]
check: When the design states a fixture rule for calls of a command (a page, a typed answer, cleared markers), does every new or rewritten call of that command in this pull request, in any item's specs, follow it, and does a check say so?
---
A rule written for one set of specs is easy to forget in the specs the same prep rewrites for other items, and those are exactly the specs a later change will break.

**Why:** c0369's re-prep (design review 003 F4, c0250 and c0394 review 002 F1): section 5 said every recording approve carries an explainer page, stub openers and a typed `y` so it survives f0339; the same prep rewrote c0250's and c0394's approve calls without any of it.

**How to apply:** after writing the specs, grep the pull request's diff for every call of the command and check each against the rule; add a structural check (the fixture's markers in each file that calls it) to the issue's `check.sh`.
