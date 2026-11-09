---
title: A fail-safe is pinned where the code acts on it
when: both
tags: [fail-safe, mutants, specs]
check: For each fail-safe the design states ("when X can't be read, keep the old answer"), is there a case that makes X unreadable where the decision is taken (end to end), not only a case on the pure rule, so a caller that bypasses the rule's fallback fails? And is it pinned at every place it is applied (each reader of the record, each owner check), not only the first one?
---
A pure rule can say "unknown means hold", while the function that feeds it turns the unknown into something else first (returns early, defaults a value). A spec on the pure rule passes either way.

**Why:** R0047 design review 002 F1: `fence.holds(true, nil, t)` was pinned, but a `stillHolds` that returned false when the start was unreadable passed every case, and it would take over every live lock wherever the kernel reader fails (no perl, sysctl refused, /proc hidden).

**How to apply:** make the input unknown at the real call site (a stand-in that refuses only that one call, answering everything else as the real tool does) and assert the end-to-end outcome. Add the act-site mutant to the Rules and mutants table.

R0047 design review 005 F2: the same two fail-safes were applied again in the takeover's owner check (`ownerHolds`), and there neither had a case: a live waiter's takeover could be removed.

Every entry point, not just the first (R0052 code review 001 F2): the start-of-run guards ran in `dispatch <id>` but not in `dispatch retry`, the command every stop message tells the user to run. List every entry point that starts the guarded work and pin the guard in each with a case.

Where the fail-safe lives (c0263 design review 008 F3, F7): a rule the caller enforces ("abort the merge when a side is not a valid record") is pinned by a pure case only when it is the pure function's return (`union` returns nil and why); one that lives only in an adapter (a main-checkout refusal, an offline refusal) needs a case that reaches the adapter with that input, or its removal passes every case.
Note (c0246 round 8 review): a "the tool refused" branch keyed on a non-zero exit also catches "the tool could not run" when it is reached through a shim (rokit exits 1 when the pinned version is missing). Check: does the failure branch tell refusal from absence (a `--version` probe), and is it pinned by a stub on `PATH` in a child process?
