---
title: A conditional step follows the order that makes its condition true
when: design
tags: [raft, order, condition]
from: R0110 design review 001 F1
check: Does any member step start with a condition about a file another member creates, and does the Order section make that condition true and pin the composed text in an RC?
---
When one member's step runs only if another member has already written something, the Order section is the order that makes that condition true, and an RC pins the composed text.

**Why:** R0110 design review 001 F1: f0199 adds its Features entry and names every leaf only when a Features section exists. Ordering f0199 first skipped both edits, and RC1 accepted the file that lost them.

**How to apply:** read each member step that starts "if … exists" about a file another member writes. Put the writer first in the Order section, each member once. Name the one departure from a literal example. Pin the composed text in an RC by comparing the whole block, and run that RC on the branch and on a scratch copy of the composed file.
