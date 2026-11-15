---
title: A criterion about new text fails on today's file
when: design
tags: [acceptance, docs]
check: Does every criterion about a section, diagram or phrase the change adds fail on the file as it is on origin/main, and does its name say only what its command checks? And does it fail for an implementation that lacks the part the name promises while it keeps the rest (a grep that any occurrence of a word satisfies is not a check of the line it names)?
---
A check that a diagram's fences are balanced, or that an old section is kept, passes on the unchanged file and proves nothing about the change.

**Why:** c0259 design review 001 F3: the diagram criterion passed on today's README, and deleting the new diagram still passed.

**How to apply:** run the check against the file on `main` before the change: it must fail for the new text. Assert what the new text contains (the diagram shows both ends), not only that the file is well formed.

**Also:** d0297 design review 001 F1: AC4 said "affected.luau's usage names the flag" and grepped for the flag anywhere in the file; the parse code satisfied it, so an implementation with no usage line passed. Anchor the grep on the shape of the thing named (here a `--   ... --flag  -- text` usage line) and add the mutant that deletes only that part.
