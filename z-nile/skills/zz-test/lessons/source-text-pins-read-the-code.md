---
title: A spec that pins source text reads the code without comments and matches every spelling
when: both
tags: [specs, source-pins, mutants]
check: Does a source-text pin read the code with comments removed and string literals as placeholders, so it fails when the required call appears only in a comment or a string, and when the forbidden thing is written another way (another pattern spelling, a long-bracket string, a format template, a helper)? Does it read past the function for a forbidden literal hoisted just outside it, or does the Rules and mutants table say what the pin leaves to the code review (a hoisted constant, a call whose result is discarded)?
---
When behaviour can't tell a copy from the shared rule (two counters with identical patterns give identical numbers), a spec pins the source: "this function calls X and keeps no pattern of its own". A plain text search makes that pin easy to pass by accident: a comment that names the call satisfies "calls X", and a second spelling of the same pattern escapes "no pattern of its own".

**Why:** c0118 design review 007 F2: `metrics.spec` searched for `boardview.rounds(` over the whole body, comments included, and recognised one spelling (`review%-%d`). c0116's own counter passed 3/3 with a comment "the same rule as boardview.rounds(paths)" and its pattern in the capture form `^design%-review%-(%d+)%.md$`.

**How to apply:** scan the body as code: drop line and long comments, collect string literals (quoted, backtick, long-bracket); require the call in the code, and forbid any literal that names the thing in any spelling (here: any literal containing `review`). Read strings as placeholders in the code you search for calls, so a call written only in a string is no call. A pin reads only the body it names, so a constant hoisted out of it escapes, and a text pin can't prove data flow (a call whose result is discarded): say in the Rules and mutants table what the pin leaves to the code review. Give the spec self-test samples for each evasion, and a mutant row for the evasion the reviewer found (c0118 design review 008 F2).

**Note (R0083 code review 002 F1):** a fix that is pinned by searching the page's source for its words is not pinned: a mutant that switches the behaviour off while leaving the words in place (`if (false && x)`, two captions swapped, a `> 1` guard) passes. Run the page's script (node and a fake DOM) and assert what it draws. Ask: does the mutant I ran for this fix keep the text the spec searches for?

**Note (R0083 code review 003 F1):** a source pin patched twice for another spelling of the same forbidden filter is the signal to stop: observe the protected call instead. A spy on the shared function that asserts every input reaches it goes red for any spelling of a pre-filter. Ask: has this pin been widened for a second spelling, and can a spy or a fixture see the call?
