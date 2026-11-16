---
title: A string another module writes is read from its producer, not copied by hand
when: build
tags: [drift, constants, jail]
check: Does a rule compare with a name or message that another module writes (a jail name, a marker, a heading), and is there a case that reads the producer's own text, so a rewording on either side turns it red?
---
A hand-copied expected string works until the producer rewords it, and a spec that uses the same copy still passes.

**Why:** R0081 code review 001 F2: `reuseplan.records` expected the jail name `none (not macOS)` for Linux, the runner writes `none (not macOS: environment guards only)`, and `plan.spec` used the literal, so nothing was ever recorded on Linux and no case noticed.

**How to apply:** match what the Design states (the prefix `none`), and add an unsequestered case that asserts the producer file still holds the exact name the rule is tested with.
