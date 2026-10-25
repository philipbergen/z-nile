---
title: An order pin anchors on text that occurs once
when: design
tags: [specs, source-pins]
check: Does each substring an order pin locates with its first match occur exactly once in a correct source, declarations and comments-stripped text included?
---
A source pin that finds the first `x = false` and checks where it sits treats any earlier occurrence (a declaration, an initialiser) as the one it meant. A correct source that declares the flag the natural way then fails, and the executor bends the code to the pin.

**Why:** R0012 execution (f0028 AC3, a reviewer's candidate in code review 001): the spec took the first `lookedThisFrame = false` as the per-frame clear, so `local lookedThisFrame = false` failed the correct code, and Camera had to declare `local lookedThisFrame, mouseHeld = false, false`.

**How to apply:** before sequestering an order pin, write the natural correct source and count each anchor's matches. Anchor on text unique to the statement meant (its context line), or assert the count.
