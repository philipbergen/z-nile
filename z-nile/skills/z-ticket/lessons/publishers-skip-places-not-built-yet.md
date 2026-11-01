---
title: The issue that publishes every place skips the ones not built yet
when: both
tags: [capture, publish, places]
check: When one issue publishes "every place" and other issues build those places later, does the publisher skip a place that doesn't exist yet (and pick it up once built), or does each builder add its own entry in its own project, so no experiment or outcome assumes a place is published before anything built it?
---
A publish step captured before the places it publishes either fails, publishes nothing for them, or forces each later place to edit another project's manifest, which a raft can't do across projects. Listing every place up front and skipping the missing ones makes each place published as soon as it exists.

**Why:** c0190 design review 004 F2: Z3's manifest ("every place of the experience") came before the issues that build the snake, invaders and asteroids places, yet E5 assumed "every place published (Z3)".

**How to apply:** say in the publisher's outcome what happens to a place that doesn't exist yet, and check each experiment's premise against the order.
