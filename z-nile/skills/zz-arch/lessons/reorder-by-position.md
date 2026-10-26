---
title: A scheduler that reorders work keys its bookkeeping by position, never by name
when: both
tags: [scheduling, ordering, bookkeeping]
check: Can the same input appear twice in the list being reordered, and what does the reorder do to the second copy's result?
---
Names in an argument list need not be unique. A reorder that maps each item back to its slot by name sends both copies of a repeated name to one slot: one result overwrites the other, and the counts and reports shrink without an error.

**Why:** c0154 design review 001 F1: the spec runner's slowest-first queue looked up `indexOf[file]`, so `tests/run -- a a` wrote both outcomes to one index and reported 6 cases instead of 12, with an empty `slowest:` line.

**How to apply:** sort positions (indices into the original list), not names, and write each result to the position it came from; add a case where one input is listed twice.
