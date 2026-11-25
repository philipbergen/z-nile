---
title: A knob that changes a runner's output is a flag, never an inherited environment variable
when: both
tags: [runner, specs, env, nested]
from: c0230 design review 001 F2 (ticket withdrawn 2026-11-16)
check: When the caller sets this knob, does the output of any nested run a spec starts (and pins) change, and if the knob is an environment variable, why is it not a flag the runner never passes to its workers?
---
Every nested run a spec starts inherits the environment of the run that started it, so a variable that changes what a runner prints changes the output every spec that pins a nested run's output reads.

**Why:** c0230 design review 001 F2: the first draft's per-file budget was `PICKMAN_SPEC_BUDGET`; on the prototype `PICKMAN_SPEC_BUDGET=0.01:0.01 lune run tests/run -- c0049/parallel-runner.spec.luau` turned it red (the nested coordinator printed a report), in-process too, and a Lune `process.env` assignment can't take a variable away from the children (zz-arch/child-env-passes-through-exec).

**How to apply:** make it a flag of the runner (`--budget`): the top process forwards its own arguments, the coordinator builds each worker's argv and never adds it, so no worker and no spec's nested run sees it. Pin it with a case whose outer run sets the flag and whose fixture spec runs a nested run, asserting the nested output is unchanged, with the outer run concurrent and in-process.

**Note** (c0178 design review 005 F15, 2026-11-24): the fixture-volume switch was an exported variable (`PICKMAN_FIXTURE_VOLUME=1`), but fourteen specs start a top-level runner inside a fixture copy by clearing only the marker, so the inherited variable made volumes (8 GiB RAM disks) inside the outer jail, left behind by cases that kill their run; a fixture copy of `check.sh` also passes the flag itself. Check: is the knob a runner flag that the top process never forwards, with the runner refusing it in any process started inside a spec run, and does a case run a nested-run spec with it set?
