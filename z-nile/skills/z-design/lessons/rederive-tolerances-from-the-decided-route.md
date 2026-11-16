---
title: When a route is decided, every tolerance in the sequestered check is re-derived from it
when: design
tags: [check-sh, decisions, sequestration]
check: For each allowance in this check.sh (a file it may change, a state it accepts, a twin's file it waves through), which delivery route or option needed it, and does the route the user chose still need it? Can a branch pass by undoing another item's work under that allowance?
---
A sequestered check written while the route was open carries the permissions of every option. After the user picks one, the others' allowances stay in a file nobody may edit during execution, and they widen the check beyond the decision.

**Why:** c0174 design review 004 F1 (medium): AC4 still accepted "c0083's `suites.spec`, whatever its content" and c0173's file by blob, which only the execution-time route needed. With the prep route chosen, a branch could write the patched spec back over a re-prep that landed on main and pass all five criteria. The same review found route letters and "route (b)" comments left in `check.sh` after the decision (F2). The sequestered file cannot be fixed after the prep lands, so the clean-up has to happen in the prep.

**How to apply:** after each user decision, list every allowance in `check.sh` and in the Design with the option that needed it, delete those the chosen option does not need, rerun the clone states, and search the check and the Design for the dropped options' names ("route (b)", "tolerated").
