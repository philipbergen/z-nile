---
title: A design that rides a path an open defect reports broken tests that path first
when: design
tags: [dependencies, experiments, defects]
check: Does any open defect or capture report the input or output path this design relies on (a control, a remote, a screen) as broken, and if so is there a pass/fail experiment on that path before `ready`, with the fix as a `depends_on` when it fails, rather than an Observed criterion at the end?
---
A design can be sound in every headless spec and still deliver nothing, because the path it plugs into does not work on the real target. When another item already says so, an Observed criterion at the end of execution finds it far too late.

**Why:** R0051 design review 004 F2: f0110's FIRE and JUMP buttons go through Controls' touch fold, while d0149 reported that on a phone touch controls don't work at all; f0110's E6 was left to OC1. Asked, the user tested: "Nothing responds", so the fix became its own defect (d0151) and a `depends_on` of f0110.

**How to apply:** for each path the design depends on, search the open items for reports against it (`./zn list backlog`, recent captures). Turn the doubt into an experiment with a pass/fail question someone can run now (the user on a device, a runtime test); when it fails, the fix is a separate item the design depends on, in the order the user sets.
