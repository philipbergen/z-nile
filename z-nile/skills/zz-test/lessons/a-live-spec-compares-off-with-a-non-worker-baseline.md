---
title: A live-layer spec compares 'off' with a run that is not a worker
when: code
tags: [live, specs, baseline]
check: Does a spec that proves a command behaves the same with the live layer off compare against a baseline taken without worker registration in the environment, so the two runs cannot both carry the effect being tested?
---
If the baseline run already registers a worker, 'same as baseline' proves nothing about the layer being off.

**Why:** f0420 step 4b (2026-11-21, spec review): the off/on comparison ran both sides with the worker variables set; a mutant that always registered passed.

**How to apply:** clear ZN_WORKER, ZN_WORKER_PID and ZN_ACCOUNT for the baseline, and kill the spec with the always-on mutant before trusting it.
