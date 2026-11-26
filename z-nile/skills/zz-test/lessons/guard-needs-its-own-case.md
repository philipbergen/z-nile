---
title: Give each guard a case only it can refuse
when: both
tags: [mutation, coverage, refusals]
check: For each refusal in the Rules table, does another check refuse the same input, and if so does the case use an input only this guard refuses, or pin this guard's own message and an unchanged state, not merely that some error occurred?
---
When two checks refuse the same input (a local check and the publish's origin check, a raft-level check and a member-level one), the case that "tests" the first passes even when the first is deleted: the second refuses for it. The guard is then untested, and a later change that weakens the second check removes both.

**Why:** c0116 prep: the mutation run left M24 (recombine's raft type check) and M27 (recombine's membership check) alive. The members' type check and the publish's origin check refused the same inputs, so their cases passed with either guard removed.

**How to apply:** in the mutation check, a surviving mutant whose case still sees a refusal means a second guard: give the case an input only this guard can refuse (an empty raft of another type), or assert the message the Design states for this guard.

R0050 code review 003 F2: `unfold`'s refusal of a done issue in its dead-raft branch had no case, so dropping it left every spec green.

**Note (c0282 prep E2):** the same holds when the second refusal is a bug. All four refusal cases of the rafting gate passed while every PR was refused for a parse error that had nothing to do with the case; only the one case that expected a merge failed. Assert the reason each case is about (and run a mutant that makes the guard accept).

**Also (f0428 review 001 F6 and review 002 N2, 2026-11-21):** option-like names (starting with `-`) were "refused" only because git errored, not because the guard refused them, and two checks called redundant were each the only guard for a real case. Assert the guard's own refusal text and that the state is unchanged, not merely that some error occurred.
