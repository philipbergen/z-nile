---
title: An Override list is confirmed by a suite run on a prototype, not by a grep
when: design
tags: [overrides, prototype, specs]
check: Was the list of promoted specs the change turns red confirmed by running the whole suite of every home on a prototype that holds every changed string, rather than by grepping for the text the author edits (specs pin rendered forms, derived strings and counts a grep for the source text does not match)?
---
A grep finds the specs that name the string being changed. A spec that pins its rendered form (a template filled with a project name, a digest, a count) names a different string and turns red unseen.

**Why:** c0239 design review 004 F1: the template's RC0 line became `--affected`, and `c0120/homes.spec` pins the rendered `... --project z-nile --full`, which no grep for `{{PROJECT}} --full` matched. The whole z-nile suite on the reviewer's prototype found it.

**How to apply:** build the prototype with every changed string and run every home's full suite once; each new red spec is an Override or a design change.
