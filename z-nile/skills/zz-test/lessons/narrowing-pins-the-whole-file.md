---
title: A narrowed promoted spec is pinned whole
when: design
tags: [acceptance, narrowing, golden]
check: When a chore narrows a promoted spec, does its acceptance pin the whole narrowed file (a normalised golden or digest), so that any edit outside the intended hunks, a deleted assertion included, turns it red, and do the Implementation steps check the pinned file's base and stop when it has moved? And does its normalisation keep line breaks wherever the language ends something at a newline (Luau `--` comments), so `"-- x\nassert()"` and `"-- x assert()"` normalise differently, and does the mutant set include "join a line onto the comment above it"?
---
Text probes for the narrowed lines miss every other way the file can be weakened: an assertion deleted from an untouched case, a loop emptied, a comment hiding code. A narrowing chore's outcome is usually "nothing else changes", and only a pin of the whole file checks that.

**Why:** R0045 design review 1 (F1): c0128's checks pinned the case titles and probed each narrowed guard, and a mutant that deleted an assertion from an unnarrowed case passed every check.

**How to apply:** normalise the file as `tests/acceptance/c0103/narrowed.spec.luau` does (whitespace, a trailing comma, ids masked, comments kept) and pin the text, or its sha256 when the file is long. Say in the spec that any later change to the file must update the pin.

R0045 design review 2 (F1): a whole-file pin taken in prep ties the executor to prep's base. "If a hunk does not apply, follow the Design" can then never pass, because the executor may not edit the sequestered pin. The steps must check the base blobs before applying and escalate for a re-prep when they differ.

R0045 code review 001 F1: c0128's golden.spec (copied from c0103's narrowed.spec) normalised with `%s+` → space, so joining an assertion onto the `--` comment line above it turned it into a comment and every pin, the text probes included, stayed green. A whole-file normalisation of code keeps the newlines that end a line comment (or marks each comment's end before collapsing). Fixed by c0156.
