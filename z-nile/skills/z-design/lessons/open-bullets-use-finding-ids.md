---
title: Open-to-the-human bullets use finding ids, or the gate cannot see them
when: design
tags: [open-list, approval, review-rounds]
check: Does every bullet under `## Open to the human` start with `- F<n>:` or `- JC<n>:` (the forms `openlist.pending` reads), so that `approve`, `status prepared` and `ready` refuse while it is unruled, and is a scope change in the list also recorded as a `Decided with the user` line once ruled?
from: c0264 design review 009 F7
---
The gate that refuses `./zn approve`, `./zn status <id> prepared` and `./zn ready` reads only `- F<n>:` and `- JC<n>:` bullets. A bullet written as `- R1 ...` or in prose is invisible to it, so an unruled decision passes.

**Why:** c0264's re-prep listed seven decisions as `- R1` to `- R7` bullets; the reviewer found the gate would let the issue be approved with all of them unruled.

**How to apply:** write each decision as `- F<n>: <the point>. Answer: ... Decision: ...` (nest sub-points inside one bullet), and when the user rules, add the `Decided with the user (date)` line to the Problem.
