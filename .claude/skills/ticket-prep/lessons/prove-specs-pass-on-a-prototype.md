---
title: Run each sequestered spec against a prototype
when: design
tags: [specs, prototype, acceptance]
check: Has every sequestered case whose module or command already exists been run against a scratch prototype, passing for the intended implementation and failing for its listed mutant, with the result recorded? And has `promote-check` type-checked the specs against a prototype that exports the design's types, rather than against a module that does not exist yet?
---
Reading a spec does not show whether a correct implementation can pass it. A sequestered case that contradicts a promoted spec, the publish rules or a command's refusal stops the executor, who may not edit it. Each such case is cheap to run on a scratch patch in prep.

**Why:** R0042 design reviews 002 F9, 003 F9, 004 F2 and 005 F3 each found a sequestered case that no correct implementation could pass: spend on an active item, which the publisher refuses, and an `appendOnly` expectation a promoted c0084 spec forbids. Every Rules and mutants row was `reasoned`, and reading missed the defect four rounds running.

R0012 execution, Phase 3: three strict sequestered specs passed at runtime but failed `promote-check`'s type check against the design's exported types. One declared `phase: string` for the `Phase` union, two read `.intent` and `.dx` off the `Effect` union without narrowing, and one reused `_` across types. Prep's dry run saw only the missing `@logic/Touch` require, which the skill allows, and with the module missing every value was `any`. The user authorized a type-only amendment.

**How to apply:** in a scratch worktree, apply the smallest patch that implements each rule, then run the case, which must pass, and the row's mutant, which must fail on an assertion. Mark the row `run` and record both outcomes in Unknowns & experiments. Keep `reasoned` only for a module that cannot exist yet, and say so. With the prototype's modules in place under `src/` of the scratch worktree, run `promote-check` there too, so strict specs are type-checked against the design's real types.

Prove it after the item's own `done` too: simulate the move to `done/` and the promotion, then run the promoted rules that judge finished files. c0115's `check.sh` named `./zn`, `.claude/skills` and `z-nile/check.sh` on lines that ran after `cd "$copy"` or `cd "$ZN_ROOT"`, which c0120's check-paths (a static reader) can't follow, and c0113's AC2 named the deleted `.claude/README.md` literally: both turned c0120's promoted `finished.spec` red only once they were finished (found by c0116's rebase). Anchor such paths at a variable, or use a literal `cd <dir>` the rule reads.

Run the `done` command itself too, not only a hand-made move: it leaves its moves and promotions uncommitted while the gate runs, so a spec that clones HEAD and overlays the working tree sees a moved item twice. c0116's retired.spec did, and only a simulated `done` of c0116 (a stub active raft in a scratch clone with no origin) found it.
