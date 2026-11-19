---
title: A new refusal prints no hint that leads around it
when: design
tags: [refusals, messages, cli]
check: When this refusal fires, does any text printed with it (a generic hint of the command, a fallback line) name a route that skips the check, and is its absence pinned by a case?
---
A command that gains a refusal keeps the generic text it printed on every failure before. If that text names another way to do the same thing, and that way does not run the new check, the refusal hands the user the way past it.

**Why:** c0135 design review 004 F3 (2026-11-19): `new issue` refused a slug an item on `origin/main` already uses, and the message still ended "(PICKMAN_PUBLISH=0 creates it locally instead)". The offline path reads only the checkout, so following the hint made exactly the duplicate the refusal exists to stop. The hint was already in the first implementation and its code review did not see it.

**How to apply:** for each refusal the design adds, read everything the command prints on that path; drop or reword any hint whose route does not apply the same rule; add an assertion that the hint is absent and a Rules row whose mutant keeps it.
