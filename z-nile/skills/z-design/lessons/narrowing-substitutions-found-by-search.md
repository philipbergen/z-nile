---
title: A rename's substitution list comes from a search, with its count pinned
when: design
tags: [overrides, narrowing, search]
check: Does each promoted-spec Override's substitution list come from a search over the base file for the old spelling (grep -c), with the expected count asserted in the check, rather than the lines the author remembered?
---
A byte-exact Override check is only as complete as its substitution list. Replacing one of four spellings of the old value leaves the other three, so a sequestered spec the executor cannot edit contradicts the new code and the issue's own check can never pass.

**Why:** c0239 design review 003 F1: narrow.py replaced `doneGate({})).toBe("full")` but c0074/done-gate.spec holds four `toBe("full")` lines; done.spec required `"affected"` for the same input one of them pinned as `"full"`.

**How to apply:** `grep -c` the old spelling in the base file, substitute every occurrence, assert the count, and run the substituted file against a prototype.
