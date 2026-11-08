---
title: Run each sequestered spec against a prototype
when: design
tags: [specs, prototype, acceptance]
check: Has every sequestered case whose module or command already exists been run against a scratch prototype, passing for the intended implementation and failing for its listed mutant, with the result recorded? And has `promote-check` type-checked the specs against a prototype that exports the design's types, rather than against a module that does not exist yet And is the prototype's base still `origin/main` for every file the specs load (the Touched modules and anything a spec reads), with the specs, mutants and gate re-run after any change there? And has the local full gate on the machine that merges run them on the prototype? And does every later step that says that gate passes match the result that run recorded?
---
Reading a spec does not show whether a correct implementation can pass it. A sequestered case that contradicts a promoted spec, the publish rules or a command's refusal stops the executor, who may not edit it. Each such case is cheap to run on a scratch patch in prep.

**Why:** R0042 design reviews 002 F9, 003 F9, 004 F2 and 005 F3 each found a sequestered case that no correct implementation could pass: spend on an active item, which the publisher refuses, and an `appendOnly` expectation a promoted c0084 spec forbids. Every Rules and mutants row was `reasoned`, and reading missed the defect four rounds running.

R0012 execution, Phase 3: three strict sequestered specs passed at runtime but failed `promote-check`'s type check against the design's exported types. One declared `phase: string` for the `Phase` union, two read `.intent` and `.dx` off the `Effect` union without narrowing, and one reused `_` across types. Prep's dry run saw only the missing `@logic/Touch` require, which the skill allows, and with the module missing every value was `any`. The user authorized a type-only amendment.

**How to apply:** in a scratch worktree, apply the smallest patch that implements each rule, then run the case, which must pass, and the row's mutant, which must fail on an assertion. Mark the row `run` and record both outcomes in Unknowns & experiments. Keep `reasoned` only for a module that cannot exist yet, and say so. With the prototype's modules in place under `src/` of the scratch worktree, run `promote-check` there too, so strict specs are type-checked against the design's real types.

**Dry-run the promotion where `done` puts the specs.** c0120 (found by c0115's rebase, which simulated c0120 done, 2026-10-21): the gate's type stage ignores `.tracker/`, so six type errors in c0120's acceptance specs (multi-returns inside `t.expect`, an untyped pair) and a stale repo-fence key surfaced only once the specs sat in `z-nile/tests/acceptance/c0120`. Copy the specs to their promoted folder in the prototype, type-check and lint them there, and run the fence allow-list scan (repo-fence) before the prep is ready.
R0044 design review 1 (F3): the prep's mutation check ran 41 mutants and all died, but the reviewer found two more stated rules (a negative score refused, an invalid run table refused) with no mutant, and both survived. List one mutant per Design sentence that states a refusal or a bound, not only per rule you wrote a case for.

R0044 design review 5 (F1): R0034 landed during the prep and changed FlowView and `Flow.Overlay`, two Touched modules. The prototype, specs and mutants had all been proven on the older base, and one sequestered case failed for every correct implementation on the new `main`. Before each review round and before the prep commit, run `git diff <prototype base> origin/main -- <Touched modules and files the specs load>`; if it is not empty, merge, rebase the prototype and re-run everything.

Prove it after the item's own `done` too: simulate the move to `done/` and the promotion, then run the promoted rules that judge finished files. c0115's `check.sh` named `./zn`, `.claude/skills` and `z-nile/check.sh` on lines that ran after `cd "$copy"` or `cd "$ZN_ROOT"`, which c0120's check-paths (a static reader) can't follow, and c0113's AC2 named the deleted `.claude/README.md` literally: both turned c0120's promoted `finished.spec` red only once they were finished (found by c0116's rebase). Anchor such paths at a variable, or use a literal `cd <dir>` the rule reads.

Run the whole item on every experimental patch, not only the spec it was written for. c0115's G14 freeze change was kept as a patch and tried against the two freeze specs; applied at the rebase, its literal mark (an old skill path) turned the item's own absence scan (AC4) red. A patch held for later is proven with `./zn check <id>` on the tree it will join.

Run the `done` command itself too, not only a hand-made move: it leaves its moves and promotions uncommitted while the gate runs, so a spec that clones HEAD and overlays the working tree sees a moved item twice. c0116's retired.spec did, and only a simulated `done` of c0116 (a stub active raft in a scratch clone with no origin) found it.

**Note** (c0117, found by c0118's simulation of c0117 done): run the promotion dry run at the promoted location too. Repo-wide scans (repo-fence's banned names, c0049's fixture isolation) read only `tests/`, so a sequestered spec passes them in place and fails the `done` gate once promoted. In a scratch clone, move the specs to `tests/acceptance/<id>` and the folder to `done/`, commit it as a simulation, and run the full gate there.

**Note** (f0146 design review 001 F5): a user rule changed a document row the specs pin after the prototype ran, and the record still said 6/6. Rerun the prototype after every spec change, including wording changes from a decision, and update the record's numbers.

c0172 design review 001 F4: E2 recorded the full gate red on `classified.spec`, and implementation step 4 still said the gate passes. A later step that says a run passed has to match the result the experiment recorded.

**Note** (c0265 design review 010 F1): read a replay's failures, not only their count. The replay of a case added in a refute failed on `listing.ok`, and the reason was that `status` already refuses in that situation; a count of "failed as expected" hid it. For each failing case, check that it fails on the line the feature adds, not on a premise about today's engine.
