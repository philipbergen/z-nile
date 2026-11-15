---
title: Name another item's command as its owner spells it
when: design
tags: [commands, consistency, dependencies]
check: Does every command the design calls that another item adds (`./zn provenance record`) use the exact name and arguments that item's design gives, not a sibling Idea's shorthand (`./zn record`)?
---
Ideas abbreviate. The owning design settles the real name, and a design that calls the shorthand either collides with an existing command or calls one that never exists.

**Why:** c0250's prep: c0249's and c0250's Ideas say `./zn record <id> unblocked`, but c0263 builds `./zn provenance record`, because `./zn record` is main's cost writer.

**How to apply:** read the owning item's Public surface for every borrowed command and use its spelling; where the owning design is not prepared yet, say which name you assumed.
