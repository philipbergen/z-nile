---
title: A new function's name is defined once in its module
when: both
tags: [luau, logic, names]
check: Does `grep -n "function <Module>.<name>"` find exactly one definition for every function the design adds or renames?
---
In Luau a second `function M.name` silently replaces the first: no load error, no type error. A new function that reuses a name the module already has breaks every caller of the old one.

**Why:** f0145 design review 002 F1: a new `Session.leave` (end the offer when the player leaves) replaced f0013's `Session.leave` (remove a member), and 11 promoted cases failed in f0013, f0025, f0065 and the Session unit spec, while the design said `Overrides: none` from a stale gate count.

**How to apply:** grep the module for every name the design adds before writing it, pick a new name when one exists (f0145 chose `Session.depart`), and rerun the full gate after the answers to every review round, not only before the first.
