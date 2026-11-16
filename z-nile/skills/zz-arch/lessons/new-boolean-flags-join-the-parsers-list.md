---
title: A new boolean flag joins the flag parser's list, or it takes the next word as its value
when: both
tags: [cli, flags, parsing]
check: For each new flag that takes no value (`--json`, `--once`, `--no-lost`), is it in `main.luau`'s `flags` list of booleans, and does a case pass it before a positional argument and assert that the positional still arrives?
---
`zn`'s `flags` treats only a listed set of flags as booleans. Every other flag takes the word after it as its value, so an unlisted `--json` followed by an id swallows the id. The command then quietly acts on no id, or on a default, and the spec passes when it puts the flag last.

**Why:** c0252's prep found its `--json` had to come last on the command line, and c0249's and c0253's preps add flags of their own (`--no-lost`, `--once`).

**How to apply:** add each new boolean to the list in the same change. Pin it with a case that puts the flag first and the positional after it, and a mutant that drops the flag from the list.
