---
title: A grammar's cases include every value its real producers emit today
when: both
tags: [grammar, models, producers]
check: Are the valid cases of this grammar taken from what its producers emit now (.models.toml, the git log, the trailers), and does one value have one spelling whichever producer wrote it?
---
Hand-written valid examples share the author's assumptions; a producer that emits a character the grammar lacks fails closed in production, and two producers that spell one thing two ways split it into two values.

**Why:** c0263 design review 001 F4: AC1's model ids were all lower-case letters, digits and dashes, while `.models.toml` has `grok-4.7` and `claude-opus-5-5-high`; a dot-less grammar would have refused every dispatched grok step, and git's `Grok 4.7` normalised differently from the live `grok-4.7`.

**How to apply:** build the valid cases from the producers' own current output, normalise through one function used by every producer, and add a case that round-trips each producer's value.
