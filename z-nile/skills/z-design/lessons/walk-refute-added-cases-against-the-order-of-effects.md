---
title: A case added while answering a round is walked against the Design's order of effects
when: design
tags: [specs, refute, ordering]
check: For each assertion added in this round's answers, which earlier command in the same case already triggers the effect it expects (and so uses it up)?
---
A new assertion placed on the wrong command passes or fails for reasons the Design does not give.

**Why:** f0265 design review 004 F1: the "taken over" notice was asserted on a command that ran after `sync` had already printed it and dropped the entry.

**How to apply:** after writing a case in a refute, list the commands in order with the effect each one triggers, and put the assertion on the first.
