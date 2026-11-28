# Idea review 001

## Findings

- F1: Problem 3 is false as a present-tense fact. No build records mutant verification today: the table is filled in prep (`z-nile/skills/z-design/SKILL.md:39`, `:56`) and `zz-execute` never mentions mutants. The pre-code approval gate is `f0465`, still a draft that depends on this ticket. The hash would break only if this idea's own move put the record inside the hashed `Test plan` (`z-nile/engine/contract.luau:26`), so the sentence states a constraint on the solution, not an existing problem.
- F2: Solution 1 gives no test that sorts a spec into "public behaviour" or "internal module shape", so a reader cannot find it true or false. "Inputs to outputs" also describes a spec that requires an engine module and calls its function, as `f0417/acceptance/contract.spec.luau` does with `@znile/engine/contract`. That is the kind of spec Problem 1 objects to, and at least 162 of the 550 z-nile acceptance specs require `@znile` modules this way.
- F3: Solution 2 already holds today, so it cannot tell the delivered ticket from the current state. `zz-execute` Phase 2 has the builder write "your own unit, contract and regression specs" under `tests/` and confirm each fails for the expected reason (`z-nile/skills/zz-execute/SKILL.md:31-33`). The same lines contradict Problem 2's claim that the design stage writes the internal unit specs: design writes the sequestered acceptance specs and the table.
- F4: Solution 4 does not say what evidence a raft owes, so "missing" cannot be decided. An easy ticket has one test and no mutation check (`z-design/SKILL.md:61`), and a ticket that changes only skill text, as this one does, has no internal unit to cover. As worded, the sentence either fails every such raft or exempts them without saying so.
- F5: The non-goals leave the nearest adjacent work unfenced. Nothing says whether the existing acceptance specs that require internal modules, or the `Rules and mutants` tables already inside the hashed `Test plan` of prepared tickets, are rewritten or left alone.

## Verdict

revise
