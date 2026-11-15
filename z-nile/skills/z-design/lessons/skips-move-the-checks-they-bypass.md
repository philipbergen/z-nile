---
title: A change that skips a path moves the checks that path had
when: design
tags: [regression, rules-and-mutants, acceptance]
check: When the change makes an existing path a no-op for some inputs (a skip, a cache hit, an early return), which promoted cases used to reach the bypassed code with those inputs, and does a mutant of that code that main kills still die on the prototype, through a new case that reaches the code another way?
---
A promoted case that still passes can stop testing what it was written for. If a change skips work for the inputs that case uses, the case now reaches the skip, not the code behind it, and a wrong edit of that code passes every check.

**Why:** c0228 design review 001 F1: MazeView's rewall started skipping walls it had drawn already. f0126's views.spec checked that walls drawn under the level-clear flash come out lit through a rewall to the same walls, which became a skip; a mutant that drew marked walls gold under the flash was killed on main and passed all 14 specs on the prototype.

**How to apply:** list the inputs the new skip takes and grep the promoted specs for cases that call the path with them. For each, name the code it reached on main, write a mutant of that code, and run it on main (killed) and on the prototype. If it survives on the prototype, add a case that reaches the code with inputs the skip does not take, record the mutant in Rules and mutants, and say in the Regression guard what the old case now checks instead.
