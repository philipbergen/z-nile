---
title: A hand-off's readings are checked against the idea the user confirmed
when: design
tags: [scope, coordination, decisions]
check: Does every reading a hand-off from a split offers "for veto" (how a user's words were taken, which of two meanings) agree with the issue's own confirmed Idea and interview answers, and where they differ, does the design follow the confirmed text, say which reading it left and why, and keep the hand-off's safety concern covered some other way?
---
A split hands the next designer the old designer's readings of the user's words, marked for veto. Nobody vetoes them; they read like decisions. Later the issue's own idea interview restates the outcome and the user confirms it, and the confirmed text can say the other thing.

**Why:** c0277 prep: c0265's hand-off kept the old worktree at its path with a marker ("rename" meant its branch) and gave the reason that a process addressing the path would otherwise reach the taker's checkout. The issue's confirmed Idea (2026-11-11) said the takeover renames the worktree so a waking process "finds its paths gone", and the interview question it answered said the work continues "in a copy, R123-1". Building on the hand-off would have shipped the reading the user's confirmation had replaced.

**How to apply:** read the hand-off's "for veto" list next to the issue's `## Idea`, `## Interview` and `## Confirmation` before building the prototype; follow the confirmed text. Keep the hand-off's reason alive as a rule of the new design (here: the renamed path is never given to anyone else), and record the reading you left under the design's readings for veto.
