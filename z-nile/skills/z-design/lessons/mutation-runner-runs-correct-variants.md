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

c0159 design review 001 F1: a chore that narrowed promoted specs for an already prepared feature (f0158) replaced a needle with a stricter spelling pin, which the feature's own design reviews had already removed from its spec as rejecting correct code. When a chore narrows for a prepared feature, run that feature's review rounds' correct variants against the narrowed specs.

c0164 design review 001 F2: correct variants were called green because the new case passed them, while another promoted spec reading the same file (f0109's place.spec, a text pin) went red. A correct variant is green only if every promoted spec that reads the mutated file stays green; the runner runs them too and reports it.

**Also:** c0284 design review 001 F3, F4: a fixture event of the wrong shape (a compaction map holding only a comment, which today's rule cuts at but c0138's does not) and a process count that also matched c0276's extra read both fail correct later code. Check: for each in-flight prep that changes a rule the fixture exercises or a command the spec counts, was its prototype run against the spec (or, when it does not apply, the rule's text read against each fixture event and the gap recorded)?
