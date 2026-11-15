---
title: An operation that pins one sha reads every path at that sha
when: both
tags: [git, races, pinning]
check: Does the operation read everything it decides on (the path list, the roots, the held set) at the one sha it pins, or does some read follow a ref that a sibling fetch can move mid-operation?
---
A command that pins one commit for its decision but lists paths through a moving ref (refs/remotes/origin/main) can judge a claim against a tree it did not pin, and a fetch from a sibling process moves the ref between the list and the attempt.

**Why:** R0100 review-001 F1 (a beat listed main's paths before pinning main, never checked that the held claim is in the claimed set there, and its watch tick read the clock outside the pcall).

**How to apply:** list paths and roots at the pinned sha (`git ls-tree <sha>`), check the held item in that listing, put every fallible read inside the pcall, and add a spec case in which main moves between the list and the attempt.
