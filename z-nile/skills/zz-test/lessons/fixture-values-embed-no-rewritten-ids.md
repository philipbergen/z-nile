---
title: A fixture value never embeds an identifier the command under test rewrites
when: both
tags: [fixtures, ids, overrides]
check: Does any fixture value (a slug, a title, a path) embed an id, path or name that a command under test rewrites, so that a case passes because the rewrite also changed the value?
---
A command that rewrites ids inside a document (renumber, remap, a move) also rewrites a fixture value that contains the id. The case then passes for a reason nobody stated, and the behaviour it was meant to pin (what the command does to a value it leaves alone) goes unchecked.

**Why:** c0135 design review 001 F4: c0082's override gave each item `slug: s-{id}`; `renumber` rewrote `s-c0010` to `s-c0021` with the id, so the renumbered copy's slug changed and audit stayed clean, hiding that a real renumber leaves the slug as it is.

**How to apply:** build fixture values that contain no rewritten identifier (spell the id's digits as letters, or give each item a name of its own), and make the two sides of a collision differ where the real case would.
