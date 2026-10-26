---
title: Narrowing "exactly these" to "at least these" keeps each member's check
when: design
tags: [narrowing, specs, mutants]
check: For each assertion a narrowing removes or widens, which code mutant did it alone catch, and does the narrowed file still catch it (through the accessor the code really uses, and with the extras limited to what the narrowing is for)?
---
An "exactly these N" check usually does two jobs at once: it pins each member, and it forbids anything else. Narrowing it to "at least N" by dropping the loop that compared every member drops the first job too, and widening "nothing else" to "anything else" lets the extras reuse the members' own values.

**Why:** c0150 design review 001 F1, F2: f0104's key map kept its ten bindings only through `View.action`, so `View.KEYS` (the table Controls binds) could be any table at all, and an eleventh key could bind `Forward` or `Jump`; both passed the narrowed spec and the whole suite.

**How to apply:** list the code mutants each removed assertion killed, keep a per-member check on the accessor the code uses, limit the extras to what the narrowing is for (here: an action of its own), and add those code mutants to the Rules table beside the spec-text mutants.
