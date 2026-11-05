---
title: A prototype's engine edits pass the type stages before the Design reports them passing
when: design
tags: [prototype, type-check, engine]
check: Did the gate's type stages (Roblox and Lune types over z-nile/) run on the prototype for every engine file the patch edits, or only a one-home `--affected` run that does not type-check the engine?
---
A one-home `--affected` gate runs that home's specs and types, not the engine's, so a patch that edits `z-nile/engine/*.luau` can carry a type error the prep never saw.

**Why:** R0075 review 001 F2 (c0184): `tooling.patch` called `skillsLib.plan(skillsLib.load("."))`, passing both of `load`'s return values to the one-parameter `plan`. The prototype's runs were `snake` and `arcade` `--affected`, so the "Argument count mismatch" appeared only at the raft's first full gate.

**How to apply:** after the last edit of the prototype, run the type stage that covers each edited engine file (the project gate's `types` stages, or `z-nile/check.sh --affected` from `z-nile/`), and record it in Unknowns & experiments.
