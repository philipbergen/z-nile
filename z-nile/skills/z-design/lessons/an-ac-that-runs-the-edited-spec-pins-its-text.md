---
title: An AC that runs the spec the fix edits also pins that spec's text
when: design
tags: [acceptance, narrowing, defect]
check: Does any AC run a file the implementation edits, with nothing pinning its text?
---
When the fix is an edit to a promoted spec, a criterion that only runs that spec checks the executor's own file. Changing the expectation, deleting the case or commenting it out all pass.

**Why:** d0416 (2026-11-18) fixed a stale case of `c0117/control-cli.spec` and its first check was "the spec passes". Design review 001 F1 listed four wrong edits that passed it.

**How to apply:** Pin the edited file against its merge base plus exactly the reviewed hunks, byte for byte, in a check.sh-only script (zz-test/narrowing-pins-the-whole-file has the pattern), and run the wrong edits as mutants in prep. A defect that edits a spec needs this as much as a narrowing chore does.
