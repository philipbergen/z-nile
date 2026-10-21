---
title: Run each sequestered spec against a prototype
when: design
tags: [specs, prototype, acceptance]
check: Has every sequestered case whose module or command already exists been run against a scratch prototype, passing for the intended implementation and failing for its listed mutant, with the result recorded?
---
Reading a spec does not show whether a correct implementation can pass it. A sequestered case that contradicts a promoted spec, the publish rules or a command's refusal stops the executor, who may not edit it. Each such case is cheap to run on a scratch patch in prep.

**Why:** R0042 design reviews 002 F9, 003 F9, 004 F2 and 005 F3 each found a sequestered case that no correct implementation could pass: spend on an active item, which the publisher refuses, and an `appendOnly` expectation a promoted c0084 spec forbids. Every Rules and mutants row was `reasoned`, and reading missed the defect four rounds running.

**How to apply:** in a scratch worktree, apply the smallest patch that implements each rule, then run the case, which must pass, and the row's mutant, which must fail on an assertion. Mark the row `run` and record both outcomes in Unknowns & experiments. Keep `reasoned` only for a module that cannot exist yet, and say so.
