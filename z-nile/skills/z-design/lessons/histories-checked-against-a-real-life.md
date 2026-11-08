---
title: A rule that reads history is checked against a real item's full life
when: design
tags: [history, trail, fixtures]
check: Does the pure case's life contain every commit a real life of that state contains (both sides of every move, the ready, start and restamp commits), not one entry per commit?
---
A hand-built history with one entry per commit passes a rule that a real life breaks: a move to `done/` is two lines (a delete and an add) in one commit, a ready commit also names the raft, and a restamp keeps every value.

**Why:** c0263 design review 006 F2: the derived rafter was the newest commit whose subject named the raft; on real done items that is the merge or the readier. The pure case had neither shape.

**How to apply:** before accepting a derivation from history, print `git log --no-renames --name-status` for two or three real finished items and build the spec's life from their shapes.
