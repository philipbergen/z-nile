---
title: A fixture's link never points at a folder above it
when: both
tags: [fixtures, symlinks, gate, lint]
check: Does any link a spec leaves under .cache point at its own fixture folder or another ancestor of itself, so that a tool which follows folder links (selene) walks it for ever?
---
Fixtures stay under `.cache` after a run, and the static stages walk the folders that hold them. A link back to an ancestor is a loop for any walker that follows folder links: selene does, and its `exclude` is applied only to the files it found, after the walk.

**Why:** R0070 (c0194), 2026-11-17: `tmp.spec`'s sweep case keeps `linky -> z-nile/.cache/c0194-tmp`, a link inside that folder. Every later static stage in that checkout ran selene without end (`selene --quiet z-nile/.cache/c0194-tmp/sweep` stopped only at a 30 s limit), which the 2026-11-15 session saw as a hang. stylua and luau-lsp finished on it.

**How to apply:** point a fixture's test link at a sibling folder made for it (`<case>-target`), never at the fixture's own folder or above; in prep, run the static stages once after the new specs ran, so a loop shows before review. The gate now keeps selene out of every `.cache` (z-nile/check.sh), but other walkers may follow links too.
