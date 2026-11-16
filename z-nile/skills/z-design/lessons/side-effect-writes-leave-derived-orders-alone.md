---
title: Values a command writes to make room are nobody's choice, so nothing derived may follow them
when: design
tags: [ordering, side-effects, derived-values]
check: Which values does this command write as a side effect (a renumbering, a default, a backfill), which orders or decisions read those values (a raft's members' best rank, a band's best card, what `next` picks), and does a spec pin that a move unrelated to each of them leaves it unchanged?
---
A command that renumbers other items to make room for one move writes values nobody chose. Anything derived from those values (an aggregate, a pick, a sort) then changes as a side effect the person never asked for.

**Why:** c0249 design review 001 F2. Dragging an issue in no raft above an unset one ranked every issue above it, raft members included. An unset raft takes its members' best rank, so the rafts swapped places and `./zn next` and `work next` picked a different raft. The person had ranked neither a raft nor a member.

**How to apply:** list every reader of the values the command writes as a side effect. Either keep chosen and side-effect values apart where the reader can tell them (a mark the one format reader parses, or the record of who set them), or make the reader ignore side-effect values. Add a spec case with the move unrelated to each derived value, asserting that the value is unchanged, and a Rules row whose mutant is the naive renumbering.
