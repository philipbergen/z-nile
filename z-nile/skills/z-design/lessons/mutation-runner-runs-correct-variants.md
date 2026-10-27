---
title: The mutation check also runs correct variants
when: design
tags: [mutants, specs, sequestration]
check: For each sequestered spec that loads source a later issue will change (an adapter, a shared module), has a list of correct variants (a right change of the kind the next issues make) been run against it, and do they all stay green? And for each prep in flight that changes a file this spec loads, has its actual prototype diff been run as a correct variant, or built into the prototype's base?
---
Mutants prove a spec fails for wrong code; nothing proves it passes for right code that differs from the prototype. A sequestered spec that rejects a correct later change can't be edited during execution, so the later issue needs an override chore.

**Why:** f0126 design review 005 F2: five correct one-line changes to Main, HudView and MazeView each turned the new stub-engine spec red; the mutation runner had only tried wrong code.

**How to apply:** beside the mutants, keep a list of correct variants in the runner (the kinds of change the issues sequenced next will make), run them with the mutants, and treat a red one as a finding against the spec.

f0126 design review 008 F1: imagined variants passed, but f0109's real prototype (colours in View, state in model attributes, one shared paint) failed two f0126 cases; with the user's "f0109 first" its prototype became part of f0126's base.
