---
title: A criterion about new text fails on today's file
when: design
tags: [acceptance, docs]
check: Does every criterion about a section, diagram or phrase the change adds fail on the file as it is on origin/main, and does its name say only what its command checks?
---
A check that a diagram's fences are balanced, or that an old section is kept, passes on the unchanged file and proves nothing about the change.

**Why:** c0259 design review 001 F3: the diagram criterion passed on today's README, and deleting the new diagram still passed.

**How to apply:** run the check against the file on `main` before the change: it must fail for the new text. Assert what the new text contains (the diagram shows both ends), not only that the file is well formed.
