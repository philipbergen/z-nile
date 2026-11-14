---
title: Sequestered specs use the test library as it is on main
when: design
tags: [sequestration, promote-check, test-lib]
check: Does every sequestered spec call only test-library functions that exist on main today (or define the helper inside the spec), since `promote-check` type-checks it against main's `tests/lib` before the issue adds anything there?
---
A sequestered spec is checked for promotion before execution, against the test library on main. A spec that calls a helper the issue plans to add (a new `seal.*` function, a new argument) fails `promote-check` in the prep, and the failure looks like the spec's fault.

**Why:** c0248's prep: a spec that called `seal.trace` with a new `through` argument failed `promote-check`; the spec now seals its landings with its own helper.

**How to apply:** write any helper the specs need inside the spec (or a sibling file in the acceptance folder), and leave the test-library change to the executor, named in Touched modules.
