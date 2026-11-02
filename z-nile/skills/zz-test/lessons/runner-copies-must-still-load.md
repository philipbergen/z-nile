---
title: A module the test runner newly requires must load in every copy of the runner
when: both
tags: [runner, specs, copies]
check: Which promoted specs copy z-nile/tests/run.luau with only tests/lib, lib and the .luaurc files, and does each copy still load and print as before?
---
Seven promoted specs run copies of the runner that hold only `tests/run.luau`, `tests/lib`, `lib` and the `.luaurc` files (run-record-merge, fence-leftovers, fence-inherited-env, lock-start-ids, c0127/reuse, c0120/runner-home, c0114/gate-cover). A top-level require of an engine module turns all of them red. Load a new module lazily, under `pcall`, only on the path that needs it, and let a missing module print what the runner printed before.

**Why:** c0181 design review 004 F2: the failure footer needed `codify` and `lessons`, which those copies do not have.

**How to apply:** `git grep -ln 'tests/run.luau' -- z-nile/tests` lists the copies; add a case that runs a copy with no engine and one failing spec.
