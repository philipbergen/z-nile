---
title: A rule enforced in several places is one function
when: both
tags: [specs, migration, drift]
check: For each rule this design checks, where else is it implemented (a migration script, another spec, the engine), and do they call one function, or does every copy pass the same planted texts?
---
A rule that a script applies and two specs check is three rules once one of them is fixed. A later finding then fixes one copy and leaves the others, and the next round finds the same hole in the copy nobody touched.

**Why:** c0115 design review 002 F1: the look-alike fix for old lesson ids (count a token only where its renamed lesson exists, and report missing ids only in ledgers) reached the rename script and AC4's scan but not AC5's `oldIds`, which then failed on the prep's own lesson that mentions `` `tracker/next` ``.

**How to apply:** put the rule in one pure function in the module that owns the format (here `skills.oldLessonIds` in `z-nile/engine/skills.luau`), and have the script and every spec call it. Where a copy can't be avoided, give every copy the same planted cases, look-alikes included, and add a mutant row per copy.
