# Refute 002: R0003 (design mode)

- F1: fixed: the design states that partial matching is top-level only, with both of the reviewer's counter-examples. New expect.spec case: `{ pos = { x = 6 } }` against the observed `{ x = 6, y = 0 }` must fail with `field "pos"`.
- F2: fixed: the step-error and never-reached cases now assert the exact replay path (`crashy-seed1-tick4.json`, `walker-seed1-tick20.json`) and the file's `steps`, `failure.tick` and state count (4/4/5 and 5/20/6).
- F3: fixed: c0010 check.sh uses `pwd -P`; c0034 now carries the same fix for the template.
- F4: fixed: the Docs section requires the words `timing exception` and a qualified no-wall-clock rule, and AC7 greps for `timing exception`. The Regression guard now describes what RC2 actually runs.
- F5: fixed: the Docs section prescribes the rule (anything driven through `@tests/lib/sim`, including whole-level simulations, goes in `tests/scenario/`; `tests/integration/ is for` cross-feature checks that don't step time) and the replacement of the integration row's example; AC7 greps for `tests/integration/ is for`.
