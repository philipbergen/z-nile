---
title: A reader's "the command ends here" rule names the nesting level it applies at
when: both
tags: [scanners, shell, nesting]
check: For each byte the design says ends a command or a call (`;`, `|`, a closing parenthesis, a `$(`, a backtick), does it say at which nesting level, and is there a case with that byte inside one of the call's own arguments?
---
In bash a `$(…)` or a backtick pair inside an argument is part of that argument; the command goes on after it. A reader that ends a call at the first `$(` or `)` it meets ends it inside its own argument.

**Why:** R0112 code review 001 F2 (medium): c0371's search-helper rule makes a helper's quoted arguments text "until the command ends", and the reader ended the call at the `$(` inside its first argument, so `has "$(./zn find c0292)/c0292.md" "tests/run is named"` read `tests/run` as a path and reported a correct check. Main read it the same way, so the corpus experiment could not show it. Deferred to c0381.

**How to apply:** state the level in the design ("at the call's own level"), track the depth the call started at, and add a case with a substitution inside an argument followed by a quoted argument.
