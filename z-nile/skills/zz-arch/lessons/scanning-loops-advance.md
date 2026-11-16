---
title: Every scanning loop advances on every pass, or fails closed
when: both
tags: [loops, parsers, input, hang]
check: Can any branch of this loop leave its position where it was, and does a hostile input (a lone backslash, an unterminated quote, an empty needle, a line end where a word was expected) reach that branch (a write through a call, a closure or an alias is not in the loop's own lines)?
---
A loop that walks a text, an argument list or a queue by a position moves it on every pass, or stops with an error. A helper that returns "where I stopped" can return the position it was given (a character it does not accept), and the loop then spins at 100% CPU for as long as the machine is up. Tests that feed well-formed input never notice.

**Enforced by** `z-nile/tests/lib/loops.luau` (a loop that is not provably advancing, or reads text, is on a reviewed list with why it ends), `z-nile/tests/lib/scanners.luau` and `z-nile/tests/lib/hostile.luau` (every text scanner runs every short hostile text under a limit) and `z-nile/engine/scan.luau` (`scan.advance` fails closed).

**Why:** c0193: raftcheck's `word()` (PR #125) returned its start index on an unquoted backslash, the loop over a check line spun, and three probes held a core each for 14 h.

**How to apply:** compute the next position, then step once at the loop's top level: `i += 1`, or `i = scan.advance(i, next)`. A loop that reads text is listed and swept: a new scanner gets a case in `scanners.luau` with a witness. `pos = b + 1` after `string.find` spins on an empty needle.
