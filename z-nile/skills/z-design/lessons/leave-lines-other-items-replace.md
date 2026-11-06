---
title: Leave the lines another item replaces
when: design
tags: [docs, coordination]
check: Do the lines this change edits or removes appear in another prepared or active item's branch diff or in its sequestered strings, and would a change that only inserts avoid the conflict?
---
A change that rewrites a line another in-flight item also rewrites conflicts with it, and a check that pins the rewrite turns red the day the other item lands.

**Why:** c0259 design review 002 F1: the README draft rewrote six "(c0117, planned)" lines; the branches of c0117, c0118 and c0121 rewrite the same lines (2 conflicts each), and the check could not pass once c0117 landed. Inserting a section instead, and leaving the old lines, merged with all three branches with 0 conflicts.

**How to apply:** `git merge-file` the change with each in-flight branch's copy of the file against the branch point; where it conflicts, insert instead of rewriting, and reconcile the old text with a sentence in the new text.
