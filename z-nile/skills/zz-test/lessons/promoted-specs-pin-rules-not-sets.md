---
title: A promoted spec pins the rule, not today's exact set
when: design
tags: [specs, promotion, overrides, structure]
check: Does any sequestered case pin an exact count or set (a module's requires, a feature's edges, a list of keys) where the rule is only a bound (stays inside Logic, declares every edge, includes this one), so that a later issue's correct addition needs an override chore against a promoted spec, and where an exact set is meant, does the Design say it is a contract?
---
A promoted acceptance spec is never edited, so an exact set it pins becomes a permanent wall: the next feature that adds a require, an edge or a key correctly turns it red and must file a chore just to narrow it.

**Why:** f0208 design review 001 F8: the place spec pinned "Play requires only Card", "Modes requires only Play" and the exact edge list, although the portal's meta spec already enforces declared edges and Logic-only requires, and f0205 had committed to pin only what later issues keep.

**How to apply:** pin the rule (requires resolve inside Logic or Shared, the needed module is among them, the edge is declared) and keep a mutant per rule; where an exact set is the point (a key map the user rules on), say in the Design that it is a contract and that a change goes through its own chore.
