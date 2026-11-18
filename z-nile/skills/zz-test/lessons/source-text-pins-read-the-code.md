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

**Also:** f0201 design review 001 F11: place.spec pinned the literal `remote.OnServerEvent:Connect(answer)` and searched raw source, comments included, for `TeleportData`; a correct adapter with another handler name or a header comment would fail, and `player["GetJoin" .. "Data"]` would pass. Where the code runs on a stub engine, a spy on the engine call (GetJoinData counted, connections counted) replaces the text pin, and the Design states the engine surface the stub serves.

**Note (R0072 review 002 F2):** a line lint that classifies a line by its last word (` end$`, `do$`) strips the trailing `--` comment first. A header comment that ends in that word otherwise hides the body. Ask: what does the lint decide for this header with a comment ending in the word it looks for?

**Note (R0072 final review 001 F2):** a line lint that proves something from one statement refuses to prove once the body opens a long bracket, because a line inside `--[[ ]]` or `[[ ]]` is not code. Ask: what does the lint decide when the line it looks for sits inside a block comment?

**Note (R0072 final review 002 F2):** a lint that refuses to prove inside a long bracket has the same duty for every other way a string spans lines or hides the characters it counts. Ask: for each character the lint counts or strips (a paren, `--`), what does it decide when that character sits inside a string literal?

**Note (R0131 code review 001 F1):** a scan that tells a use from a comment line by line stripped `%s%-%-%s.*$` from every Luau line, so the shell form of a call held in a string (`"lune run z-nile/affected -- --project z-nile --own-acceptance"`) lost its flag as if ` -- ` began a comment, and the guard counted no use. Decide the comment marker only outside a string literal (quotes and backticks, with escapes), and feed the scan a string that holds the marker before the token. Ask: does the scan's own spec give it a string literal containing the comment marker ahead of what it counts?
