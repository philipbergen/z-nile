---
title: Affected specs come from the files the change touches, not their folders
when: design
tags: [selector, affected, overrides]
check: Does the Affected specs command name the files the prototype's diff changes (`git diff --name-only`), and does its count match a run on those files?
---
The selector maps a folder argument differently from the files inside it, so a list made from feature folders can miss specs that watch a file in them, and the override check and z-raft read that list.

**Why:** f0234 design review 001 F4: `Logic/Hop` and `Logic/View` as folders gave 221 specs, the two `init.luau` files 241; the 20 missed included f0126/adapters.spec, which the issue's own AC5 runs.

**How to apply:** generate the list from the prototype's changed files and keep the Touched modules bullets for attribution; when the two differ, say so in the document.
