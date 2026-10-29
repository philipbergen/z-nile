---
title: A Recommendation that offers a spec case or a check.sh AC says which one
when: design
tags: [check-sh, promotion, recommendation]
from: c0137 design review 003 (the reviewer's candidate lesson)
check: When a Recommendation offers a spec case or a check.sh AC, does it say which—putting a rule in a promoted spec case and today's exact text in an unpromoted check?
---
A spec case is promoted at `done` and runs in every gate after; a check.sh AC runs at the item's own check and `done`, then never again. Offering both as equal leaves the author to pick the one that turns today's text into a permanent rule.

**Why:** c0137 design review 002 offered "scans.spec (or a check.sh AC)" for running three finished criteria whole; the author picked the spec, and review 003 F1 had to move it out, because the criteria's text pins (`add/add`, `/z-ready`, …) would have reddened the z-nile gate on ordinary skill edits.

**How to apply:** when a recommendation names where a new check goes, weigh it against zz-test/promoted-specs-pin-rules-not-sets: a claim about today's tree goes in check.sh; a rule the change restores goes in a spec.
