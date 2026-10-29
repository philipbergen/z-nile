---
title: A value two conventions could mean gets one reading, chosen from its own text
when: design
tags: [conventions, exemptions, paths]
check: For each value this rule reads (a path, an id, a name, a per-loop count versus a sum, an order), which readings could it have, which one does the rule pick from its text or history, and does a case show that the reading not meant exempts or matches nothing?
---
When a field is written in two conventions (Touched modules repository-relative in some documents, home-relative in others), accepting both readings for every value doubles what each value claims: an exemption meant for one path now covers a second path nobody creates.

**Why:** c0141 design review 001 F1: check-paths read every Touched entry both ways, so `z-nile/skills` also exempted `z-nile/z-nile/skills/new`, and `src/New` in pickman also exempted the root's `src/New`, which main reported before.

**How to apply:** pick the reading from the value's own text (a registered prefix, what exists where), state the rule, and add a fixture case per reading plus one where the wrong reading would have matched; a mutant that accepts both must fail.
