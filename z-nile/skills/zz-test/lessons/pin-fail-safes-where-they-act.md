---
title: A fail-safe is pinned where the code acts on it
when: both
tags: [fail-safe, mutants, specs]
check: For each fail-safe the design states ("when X can't be read, keep the old answer"), is there an end-to-end case that makes X unreadable at every caller that acts on it, not only on the pure rule or the first reader?
---
A pure rule can say "unknown means hold", while the function that feeds it turns the unknown into something else first (returns early, defaults a value). A spec on the pure rule passes either way.

**Why:** R0047 design review 002 F1: `fence.holds(true, nil, t)` was pinned, but a `stillHolds` that returned false when the start was unreadable passed every case, and it would take over every live lock wherever the kernel reader fails (no perl, sysctl refused, /proc hidden).

**How to apply:** make the input unknown at the real call site (a stand-in that refuses only that one call, answering everything else as the real tool does) and assert the end-to-end outcome. Add the act-site mutant to the Rules and mutants table.

R0047 design review 005 F2: the same two fail-safes were applied again in the takeover's owner check (`ownerHolds`), and there neither had a case: a live waiter's takeover could be removed.
