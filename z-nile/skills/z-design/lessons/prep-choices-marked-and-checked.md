---
title: Every product choice a prep makes is marked (prep) and checked against the decisions file
when: design
tags: [scope, product-decisions, docs]
check: Is every word of a decisions-file entry before its (prep) marker traceable to the capture or to a user line, and has each prep choice (a colour, a gesture, a timing, a trade-off) been checked against what that file already records about the user (how they see a colour, an open decision it touches), with its cost stated so the user can veto it?
---
A project's decisions file (pickman's `game-design.md`) is the user's. When a prep writes its own choices there without the **(prep)** marker, or before it, they read as the user's and nobody knows they can veto them. A choice made without reading what the file already says about the user can contradict it.

**Why:** R0051 design review 001 F2 and F3: f0110's bullet put the prep's choice of buttons over gestures, the colours, the captions and finger-down firing before the marker, never stated finger-down's cost (a look drag starting on FIRE spends a shot), and picked cyan to tell FIRE from a white button although the file records that the user sees that cyan as white.

**How to apply:** start the entry with only what the capture says, then the **(prep)** marker and every choice after it, each with its cost. Search the decisions file for the choice's terms (the colour value, the control, the timing) and answer what you find; link the choice from any open decision it now depends on.
