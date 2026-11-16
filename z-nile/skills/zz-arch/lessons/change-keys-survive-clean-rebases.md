---
title: A "same change" key survives everything a clean rebase does to a diff
when: design
tags: [git, rebase, patch-id, keys]
check: Does this "same change" key survive what a clean rebase can do to a commit's diff (moved line numbers and context, new blob ids, a rename of the file on the new base, a different order of file sections), and does the key's own spec have a case for each? Does it drop path and header lines only from the header, so a removed `--- …` content line still counts?
---
A key read from a fresh diff of a rebased commit changes with everything the base changed around the commit, not only with the commit. Line numbers, the hunk header's function context and blob ids move whenever the base moves; a rename on the new base moves the path (merge-ort follows renames, so the rebase is clean); and git orders file sections by path, so a rename can reorder them. A key that keeps any of those refuses a layer that lost nothing.

**Why:** c0300 design review 001 F2: `changeKey` kept the `diff --git`, `---` and `+++` lines, so a clean rebase over a rename on `main` changed the key and restack would have refused the layer as "part or all of its change is already there". While fixing it, dropping `---`/`+++` everywhere would have hidden a removed Luau comment (`--- note` in a -U0 patch).

**How to apply:** key each file section by its mode lines, its changed lines and its binary patch only; drop `diff --git`, `index`, `---` and `+++` from the section's header only; cut hunk headers to `@@`; sort the sections. Pin each of moved lines, another path, another order, a missing section, a `---`/`+++` content line, and an emptied commit with its own case.
