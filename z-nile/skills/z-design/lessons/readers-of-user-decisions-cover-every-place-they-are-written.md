---
title: A reader of the user's decisions covers every place the repository records them
when: design
tags: [decisions, ask, parsing]
check: List each place a user decision or ruling is recorded (Problem lines, bulleted and bold lines, Ruled bullets under Open to the human, other sections, confirmations added after capture); is there one spec case per place, and does the reader take only the decision, not the finding or the author's answer?
---
A reader that matches one spelling in one section misses the others, and each miss makes a later reviewer judge against an ask that leaves out something the user decided.

**Why:** c0262 design review 001 F4: the view's ask matched `Decided with the user (` at column 1 of the Problem only, and missed bulleted lines, rulings under Open to the human, decisions in other sections and the confirmation c0260 adds after the capture.

**How to apply:** read from the approved base document, match marks inside the line after stripping list and bold markers, take a ruling's Decision clause and the user's word only, and add a spec case for each place.
