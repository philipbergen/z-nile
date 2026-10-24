---
title: A rule decided for one item's check stays in that check's call
when: both
tags: [scope, commands, exemptions]
check: Does this exemption change the command's answer for callers the decision didn't name (other arguments, other commands that share the logic, after the item lands)? Is it applied only for the call the decision names, with an end condition that turns it off by itself, and is what it skipped still shown somewhere?
---
A user decision that exempts something for one item's check (a freeze, a gate, a readiness test) is about that check. Put into a general command for every caller, it silently changes the command's answer for callers nobody asked about, and it outlives the item: a later branch that reuses an exempt name is exempt too.

**Why:** c0120 code review 011 F1: the user exempted the branches stacked on c0120's prep, and five approved by name, from c0120's freeze (AC16, `./zn busy tracker src tests`). The exemption went into `./zn busy` for every path set, so with no paths (compaction's set) busy printed nothing while `./zn compact` refused on six branches, and the tracker skill's `busy` row was false. The names were fixed in the engine with no end condition.

**How to apply:** apply the exemption only for the call the decision names (here: explicit paths), and only until the item lands, read from a fact that changes when it does (here: `origin/main` still holds the old layout's mark). Name each skipped thing on stderr, uncounted, so the answer stays honest. Add a case for each boundary (another caller, after landing) with a mutant that drops it.
