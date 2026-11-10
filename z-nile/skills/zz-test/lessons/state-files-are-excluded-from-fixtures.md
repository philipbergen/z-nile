---
title: A new tracker-state file joins the fixtures' exclusions
when: both
tags: [fixtures, state, engine]
check: Does the design add a file the engine reads as tracker state under a folder the harness copies into every fixture (`z-nile/*` through `engine.copy`, `engine.PATHSPECS`), and is it in `engine.STATE` and the pathspecs, so that a fixture's base holds the real repository's copy only when its seed gives one?
---
A file the engine reads from `origin/main` and a fixture copies from the checkout makes every fixture inherit the real repository's copy the day it is committed. A rule keyed on that file is then in force in every spec that drives the command, and specs that passed on the prototype (which never held the file) go red on the merge.

**Why:** c0283 design review 001 F2: the frozen list `z-nile/provenance-exempt.txt` is committed by the raft's last step; `engine.copy` copies every `z-nile/` entry except `engine.STATE`, so `freeze.spec` and `tooling/ready-members.spec` went red with the file present, and 51 spec files drive a door or `audit`. The Overrides had been measured on a tree that stops existing at that step.

**How to apply:** add the file to `engine.STATE` and an exclude to `engine.PATHSPECS` in the same change, put a placeholder of the real file in the prototype so every later run holds it, and give the file's rule a case that a fixture without a seed has none.
