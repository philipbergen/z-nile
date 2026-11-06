---
title: A split issue's inherited user decisions are checked against each other
when: design
tags: [scope, decisions, split]
check: When the Problem quotes several user decisions inherited from the issue it was split from, do any of them disagree about the same step (two decisions about one command's gate, mode or order), and has the user been asked which governs before the design follows one?
---
A split copies the parent's decision lines, and decisions made on different days can contradict each other without anyone noticing, because each was right when made. A design that silently follows the older one builds the wrong thing and the review is the first reader to see the clash.

**Why:** c0239 design review 001 F1: the 2026-10-26 decision ("done runs every spec and the merge accepts that run") and the 2026-10-31 one ("done is affected-only, the merge keeps one full gate") both sat in the Problem. The draft built the older (a reuse mechanism, six findings of fallout). The user chose the newer on 2026-11-04.

**How to apply:** before the first draft, put the decisions side by side by step (done, land, merge, review) and ask the user about any step with two answers.
