---
title: A missing request means what the screen showed
when: design
tags: [authority, defaults]
check: When the server gets a request without a value (no level, no choice), what did the player's screen say would happen, and is the server's default exactly that, rather than the server's own preference?
---
A server default that differs from the screen gives the player something they did not ask for.

**Why:** f0148 design review 001 F1: a press with no level (START GAME, which says level 1) stored the player's best, so a player whose picker had not loaded, or a server-side press, played the best level at best-level points.

**How to apply:** take the default from the screen's own text and pin it with a case for the missing value and for a value that is not allowed.
