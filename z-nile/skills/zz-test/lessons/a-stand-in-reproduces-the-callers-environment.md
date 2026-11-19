---
title: A stand-in for a nested run reproduces what the real caller sets
when: both
tags: [dispatch, fixtures, mutants]
check: Which variables does the real caller set that the stand-in leaves out, and does a mutant keyed on one of them survive?
---
A case that fakes "run from inside an author's step" by setting one variable proves the code's behaviour for that variable only. The real parent sets several, and a wrong implementation keyed on another one passes.

**Why:** d0416's first acceptance spec set only `ZN_DISPATCH_DIR` for its nested case. A real nested step also inherits `ZN_PUBLISH_BROKER`; the mutant `if land and (process.env.ZN_PUBLISH_BROKER or "") == "" then` passed the spec and both of d0415's (design review 001 F3, 2026-11-18).

**How to apply:** Drive the real caller (here: dispatch the author step with the fake CLI in `waitreview` mode) for at least one case, and add the mutant keyed on a variable the stand-in omits.
