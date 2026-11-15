---
title: A condition joined to an action by && ... || exit is not an if
when: both
tags: [shell, specs, fixtures, gates]
check: Does any shell a spec writes (a gate script, a stand-in, a hook) guard an action with `cond && action || exit N`, so that a false `cond` runs the `exit`? Is each such guard an `if cond; then action || exit N; fi` instead?
---
In bash `a && b || c` runs `c` whenever `a` is false, not only when `b` fails. A gate script written as `[[ $n == 1 ]] && ( push a racing commit ) || exit 9` does its work on the first run and exits 9 on every later one, so the second gate run "fails" for a reason that has nothing to do with the code under test.

**Why:** c0258's prep (2026-11-15): two race cases expected the gate to run twice, and both failed with "the gate failed: nothing was pushed" on the prototype that was right; a third case passed only by accident, because its gate was meant to fail on its second run anyway.

**How to apply:** write the guard as `if [[ $n == 1 ]]; then ( ... ) || exit 9; fi`, and when a gate is meant to fail, make that its own last line, so a mutant of the code under test, not the script, decides the case.
