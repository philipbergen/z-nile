---
title: A spec sets the host markers it depends on
when: both
tags: [specs, ci, jail, portability]
check: Does any case depend on what the runner sets for this host (`PICKMAN_TEST_JAIL`, `PICKMAN_FENCE_SPECS`, `PICKMAN_TEST_FENCE`, the OS)? Does it set each of those itself? Run with every value `PICKMAN_TEST_JAIL` takes (`sandbox-exec`, Linux's `none (…)`, `outer sandbox (…)`), does each case still test what its name says?
---
A case that inherits the runner's jail markers tests whatever the host it runs on happens to be. It passes where its author ran it, and elsewhere it fails or, worse, passes without reaching the path it names. Prep, mutation runs and the gate all running on one macOS machine never show this; CI's Linux gate does, after the spec is promoted.

**Why:** c0120 design review 003 F1: `homes.spec`'s jail case relied on the runner's `PICKMAN_TEST_JAIL=sandbox-exec`. On Linux (`none (not macOS: …)`) and in an outer sandbox (`outer sandbox (…)`) the home fence took its refusal branch, so the case failed. Its leftover folders then failed two later cases. The symlink case's "in the jail" run never reached the marker path there at all, so the mutant it was meant to kill would survive on CI.

**How to apply:** give every run that depends on a host marker an explicit environment with all of them, plus an explicit no-marker run beside it. Stand in for the host's protection with something the fixture controls (`chmod 555` for the jail), and fail loudly when the stand-in doesn't hold (root ignores `chmod`). Don't skip the case off the host, which leaves it untested on CI. Then run the spec, and its mutants, with each value the runner can set. A temporary relabel of the run is enough when the real host isn't at hand. Record each run in the Verification log.
