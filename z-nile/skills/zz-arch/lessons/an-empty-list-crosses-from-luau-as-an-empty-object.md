---
title: An empty list that crosses from Luau as JSON arrives as an empty object
when: both
tags: [app, facts, json, go, luau]
check: Does a list that Luau writes as JSON for another language's reader have a reader that accepts `{}` as the empty list, and does a test feed that reader the text the real encoder wrote for an empty list?
from: f0437 step 4a defect on real data, 2026-11-23
---
Luau cannot tell an empty list from an empty map, so Lune's JSON encoder writes an empty list as `{}`. A reader that decodes the field as an array fails on it.

**Why:** the Approvals view said "the approval facts have an unexpected shape" on the real facts file: 7 of 13 tickets had `"guesses":{}`. The Go reader decoded every list field as a slice, and its tests used hand-written fixtures that always had `[]`, so the form the engine really writes was never tried.

**How to apply:** give the reader one list type that accepts `{}` (and only the empty object) as an empty list and writes `[]` onward; pin in a Luau spec what the encoder writes for an empty list, with a comment naming the reader; and keep a fixture in the reader's tests copied from that real output.
