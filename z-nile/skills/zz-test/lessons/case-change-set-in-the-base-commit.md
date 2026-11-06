---
title: What a case's change set must not see goes in the fixture's base commit
when: design
tags: [specs, fixtures, change-set]
check: When the code under test diffs against a merge base (an affected selection, a scope, a change-set reader), does the fixture's base commit already hold every file the case needs but must not count as changed (a stub gate, declared inputs), and does the change-set reader print nothing in the fixture before the first case writes anything?
---
A commit on the work branch is part of the branch's change set. A stub or a declaration committed there is seen as a change by every case, so a correct implementation fails every "one project" expectation and the mutants the "ALL" cases were written to catch still pass.

**Why:** c0239 design review 003 F2: stop.spec committed its stub gate script and its declarations on `work`; a probe with the real change-set reader showed every case's change set held them.

**How to apply:** put such files in the base commit (`gatefix.make`'s `setup`), and add a first case that the reader answers "nothing changed" before any write.
