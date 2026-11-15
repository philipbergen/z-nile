---
title: A loop that writes only at the end loses the paid passes when a limit kills it
when: design
tags: [loops, models, dispatch, timeouts]
check: Is the loop's wall time measured against the dispatcher's tool_seconds and the Bash tool's timeout, does it write each pass as it completes (the binding file last), and does it beat while it works?
---
A loop of model calls that holds its results until it ends makes every call a gamble on the limits of the processes above it: a dispatcher that stops a quiet tool call, an interactive shell with a default timeout, one unparseable answer at the last call. The passes already paid for are gone, and a retry runs the same loop into the same limit.

**Why:** c0260 design review 011 F2: `./zn idea` looped up to seven model calls and wrote nothing until the end, under a 900 s `tool_seconds`.

**How to apply:** write each pass when it completes, in an order that never leaves a binding file (a review) naming a document that lacks that pass; have the command beat into the dispatched step's folder while a call runs; give the skill's step the long timeout; add an experiment that measures a real run's wall time against both limits; add a spec case where the second call fails and the first pass stays.
