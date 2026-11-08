---
title: An Override search names every way a spec can require the module
when: design
tags: [overrides, acceptance, search]
check: Does the Override search, and the check that re-runs "every spec that reads it", name every spelling a spec uses to require each Touched module (`@znile/engine/<m>` and `@scripts/tracker/<m>`, as `.luaurc` lists them) as well as the path, and was the resulting list run against the prototype?
---
A search for the specs a change touches that uses one alias spelling of a module finds only the specs that spell it that way. The same module is required through another alias by older specs, which then go red at execution on an override the design never declared.

**Why:** c0261 design review 001 F1: the Override search used `engine/ledger`, and two c0084 specs (the phase list and the metrics phases) require the ledger as `@scripts/tracker/ledger`; adding a ledger phase turned both red, and `affected` printing `ALL` hid it until the gate.

**How to apply:** list the aliases in `.luaurc` that reach the Touched module, grep for every spelling (and the file's basename), paste the search and its list in Affected specs, make the issue's regression check use the same pattern, and run that list on the prototype.
