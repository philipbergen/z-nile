---
title: A design that marks items names every claim kind and where each is drawn on the opening view
when: design
tags: [board, claims, coverage]
check: For every kind of claim the marks can land on (an issue's own claim, a raft's own claim that stamps only the raft, a readied raft whose members carry its stamp), does the design say where it is drawn on the view the page opens on, and does an engine-level spec seed that kind and fail when it is dropped?
---
A mark that is correct for issues can be invisible for rafts: a raft is a band head on the Board view, not a card, and a claim by z-raft stamps the raft only.

**Why:** c0276 design review 002 F1: the verdict marks drew on cards, but a rafting claim has no card; the Board view showed nothing, and a mutant dropping every raft verdict at the engine edge passed the engine spec, which seeded issues only.

**How to apply:** list the claim kinds from the claim rules (zz-rules, Rafting and Ready), find each in the default view's markup, and seed one of each at the engine edge.
