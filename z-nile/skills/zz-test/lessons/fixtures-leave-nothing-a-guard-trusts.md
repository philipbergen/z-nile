---
title: A fixture removes every folder a guard would trust, passed or failed
when: both
tags: [specs, fixtures, guards]
check: Does this spec create a folder whose name or place a guard treats as the run's own (a stub, bin or guard folder, a registry), and is it removed after every case (a `pcall`, the teardown, then the error) with a last case that asserts it is gone?
---
A guard that believes "the run's own" folders cannot tell a live run's from one a spec left standing. A spec that builds such a folder under a checkout's `.cache` and never removes it hands every later launcher a trusted directory.

**Why:** c0123 design review 008 F3: `cleanenv.spec` left `pickman-guard.BBBB` and `pickman-run.AAAA/bin` under the home's `.cache` in every checkout; with that folder on `PATH` every launcher passed forged `GIT_CONFIG_*` and `GIT_SSH_COMMAND` on, and `./zn`'s own git read a forged `core.fsmonitor`.

**How to apply:** build such fixtures per case, wrap each case so the fixture is removed whether it passes or fails, end the spec with a case that asserts nothing is left, and make the guard believe only folders a runner registered so that a leftover proves nothing either way. Stubs a spec puts on `PATH` go in the run's own temp folder (`fixture.stubDir`), which the runner removes. Mutant: the teardown dropped.
