---
title: A check that an input is declared looks up the exact key with the selector's own parser
when: design
tags: [selection, inputs, specs]
check: Would a declaration row with the wrong path prefix, or naming a spec that does not exist, still pass this check? Is the row looked up by the selector's parser and the exact key it uses (`tests/acceptance/<id>/<spec>` relative to the home), and is a declaration needed at all (do the touched paths already force the project's full run)?
---
A substring match (`acceptance/c0247/docs.spec.luau\tpath`) passes a row whose key points at no spec, because the parser never checks that the spec exists, and the declaration is then dead. And a declaration is only needed where the selector would not pick the spec anyway: a path under `z-nile/` outside `tests/` already forces z-nile's full run.

**Why:** c0247 design review 002 F2: the draft's rows and AC5 used `acceptance/c0247/…` against c0165's `tests/acceptance/c0247/…` keys; `./zn check` passed 7/7 with rows that selected nothing. The files were under z-nile's forcing rule, so no row was needed at all.

**How to apply:** first ask whether the selector's forcing rules already cover the touched paths; if a row is needed, check it with `select.parseInputs` and the exact key.
