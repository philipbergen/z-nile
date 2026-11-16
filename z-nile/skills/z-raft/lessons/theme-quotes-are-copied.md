---
title: A Theme quotes each decision by copying it
when: design
tags: [raft, theme, decisions, quotes]
from: R0101 design review 001 F1
check: Does `git grep -F` of every string the Theme puts in quotation marks find it in the project's game-design.md or in the member's document, and does every quoted decision in each member's Decisions this relies on appear, including a ruling that member copied from an unlanded prep?
---
A raft's Theme carries the user decisions its members quote into the execution prompt. A paraphrase inside quotation marks reads as the user's words and can say something else.

**Why:** R0101 design review 001 F1: the Theme quoted "Ghosts are 10% slower, as a tuning multiplier on the level tables", a sentence found nowhere in the repository. The real row says ghosts run at 1 / 1.1 of the classic speeds, which is not 0.9 times them. The Theme also left out the decision c0176's design quotes.

**How to apply:** copy each member's quoted decision line from its Design, then `git grep -F` each quoted string before the raft's review.

**Note** (R0110 design review 001 F2): copy every line of a member's "Decisions this relies on, quoted", including a ruling that member copied from an unlanded prep. The copies come from the member's text, not from the prep branch the member names. `git grep -F` each quoted string against that member before the answer lands.
