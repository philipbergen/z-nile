---
title: When a rule moves where something is written, reread the sentence each writer reads as it writes
when: design
tags: [restated-rules, skills, docs]
check: When this design changes where or how a thing is written (a note, a record, a file), which sentence does each writer read at the moment of writing (a skill's role bullet, a step, a template comment), and read literally under the new rule, does it still lead to the new form?
---
A rule that moves a write (a new file instead of an appended paragraph, a new folder, a new command) is stated where the format lives, but the writers follow the sentence in front of them when they write. A sentence that never named the old place can still steer them back to it once the rule changes: "writes a new file only when none does" was neutral while a note was a paragraph, and became the opposite of the rule once a note was a file.

**Why:** c0291 design review 001 F1: the design stated the note file in zz-rules Items and kept the lead bullet of every skill's `## Lessons` paragraph because it "does not say where a note goes"; under the new rule it told every lead not to write a new file for a note, so the conflicts the issue removes would have kept coming.

**How to apply:** for each writer of the moved thing, find the sentence it reads at the moment of writing (grep the skills for the verb: "adds a note", "appends", "writes"), read it as if the new rule were already in force, and change every copy that now points the wrong way, with a spec that walks every copy.
