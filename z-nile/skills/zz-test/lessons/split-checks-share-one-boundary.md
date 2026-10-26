---
title: A check that splits a file into a part that may change and a part that must not cuts both with one reader
when: both
tags: [specs, boundaries, pins]
check: When a check splits a file into a changeable part and a fixed part, do both sides use one boundary reader, and does a line inserted exactly at the boundary turn some check red?
---
Two readers that each find "their" part of a file leave the text between them unchecked: one stops at the first line that is not a comment, the other starts at the first `local`, and a code line placed between the two is in neither.

**Why:** c0134 design review 001 F1: header.spec cut accept.spec's header at the first non-comment line, while check.sh AC2 compared the body from the first `local` line. A code line inserted between the header and `local fs = …` passed all three criteria.

**How to apply:** write the boundary once (a small module both the spec and the check use), cut both parts with it, and add a mutant that inserts a line exactly at the boundary.
