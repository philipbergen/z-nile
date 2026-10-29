---
title: A filter proves it keeps the lessons past reviews needed
when: design
tags: [acceptance, specs]
check: Would this filter, including the skills a mode or path exercises, have shown each past reviewer the lessons their findings were later harvested into?
---
A selector that only shows it returns fewer lessons can pass by dropping the ones the review needed. Recall is the count of harvested lessons the filter would still have shown, over the lessons a past review's harvest names.

**Why:** c0166 design review 001 F1: the maze count (how few lessons remain) passed for a selector that dropped `spec-design-correspondence` and the check.sh lessons, which apply to every design.

**How to apply:** replay `design-review-NNN Fk: <lesson ids>` (and the code-review form for a build filter) from the harvest ledgers already in the tree. Count a lesson only when its `when` matches the review. State a pass bar and a fallback that does not drop a captured outcome. A filter that keeps under the bar changes its inputs, not the outcome.
