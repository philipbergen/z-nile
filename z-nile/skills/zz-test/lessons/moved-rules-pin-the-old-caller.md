---
title: A rule moved out of a promoted spec stays protected, and its old caller is pinned to use it
when: both
tags: [promoted-specs, refactor, sequestration]
check: When a rule moves from a promoted or sequestered file into a module, does it stay where "never edit promoted specs" protects it, and does a criterion fail if the old file keeps (or regains) its own copy?
---
Moving a rule into a shared module so a new spec can test it has two traps: the module escapes the protection the promoted file had (any later item can weaken it with no Overrides line), and "the module exists and passes" is met while the gate still runs the old file's own copy.

**Why:** c0141 design review 001 F2, F3: the scanner moved from c0120's check-paths spec to `z-nile/tests/lib/`; AC2 passed with c0120's spec untouched, and the library sat outside the promoted folder.

**How to apply:** put the module in the promoted folder beside its spec (as c0120's `rewrites.luau` and `finished.luau` are), name it on the Overrides line, and pin the old caller: it requires the module, calls its entry point, and defines none of the moved functions.
