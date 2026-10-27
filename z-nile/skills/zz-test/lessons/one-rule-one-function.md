---
title: A rule enforced in several places is one function
when: both
tags: [specs, migration, drift]
check: For each rule this design checks, where else is it implemented (a migration script, another spec, the engine), and do they call one function, or does every copy pass the same planted texts? And where the rule reads a format, is it built on that format's own reader rather than on a pattern over its text?
---
A rule that a script applies and two specs check is three rules once one of them is fixed. A later finding then fixes one copy and leaves the others, and the next round finds the same hole in the copy nobody touched.

**Why:** c0115 design review 002 F1: the look-alike fix for old lesson ids (count a token only where its renamed lesson exists, and report missing ids only in ledgers) reached the rename script and AC4's scan but not AC5's `oldIds`, which then failed on the prep's own lesson that mentions the old root's counter file by its path.

Round 003 F1 found the third hole in the same rule: it treated a whole `harvest.md` as ids, but a note's text and a one-off's reason are prose, so `review/x` in a note failed AC5. The fix was not a fourth narrowing of the pattern but the format's own reader: `lessons.parseHarvest` says which tokens are ids.

Round 004 F1 found the gap that reader left: `parseHarvest` skips every line that isn't a `- ` bullet, so a prose paragraph or an indented sub-bullet naming an old id was in neither rule. A rule built on a reader covers the lines the reader skips: the parsed parts take their rule, and every other byte of the file takes the general one.

**How to apply:** put the rule in one pure function in the module that owns the format (here `skills.oldLessonIds` in `z-nile/engine/skills.luau`), and have the script and every spec call it. Where a copy can't be avoided, give every copy the same planted cases, look-alikes included, and add a mutant row per copy.

R0050 code review 004 F1: "which command gives back this active issue" was decided twice, by audit (no raft folder means missing) and by `stop <issue>` (anything `store.find` finds is live). In the states between them, each refusal named a command whose own rule then refused the item. That made three rounds on one mechanism; one function (`audit.raftHolds`), called by both, ended it.

c0144 prep: the color rule lives in term.decide and again in ac.sh (shell must decide for its own stdout). Every `./zn check` case passed with ac.sh's TERM=dumb test removed (mutant M33), because the engine, deciding first, passed NO_COLOR to check.sh and hid ac.sh's copy. A copy that a caller pre-empts needs a case that reaches it with no caller in between (here `bash check.sh` on a pty).
