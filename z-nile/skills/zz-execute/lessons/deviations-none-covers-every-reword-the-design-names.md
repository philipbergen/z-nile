---
title: "Deviations: none" is checked against every change the Design names, comments included
when: build
tags: [verification-log, deviation, design]
check: For each sentence of the Design that says something "is reworded" or "is changed" (a comment, a label, a message), does the diff contain that change, before the Verification log says "Deviations: none"?
---
A Design lists small edits that no spec sees (a comment reworded because the code beneath it changed meaning). Copying a prototype carries the code and leaves those edits behind, and the log then claims no deviation from a Design the diff does not follow.

**Why:** R0088 code review 001 F2 (c0246): the Design said two `graph.luau` comments are reworded; the prototype copy skipped them, the Verification log said "Deviations: none", and a comment still said Rojo has "both forms" after the walker learned of a third.

**How to apply:** after copying a prototype, grep the Design for "reworded", "reworded:", "is changed" and "comment", and find each in the diff; write the ones you did not make as deviations.
