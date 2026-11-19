---
title: Sending a player away also stops what they can do here
when: design
tags: [teleport, authority, server]
check: What does the player get here if TeleportAsync errors, TeleportInitFailed fires, the destination is unset, or the client never leaves?
---
A teleport needs the client to cooperate and can fail in several ways. A server decision that ends in "send the player elsewhere" and leaves the run going here gives the player the thing the decision refused whenever the teleport does not happen.

**Why:** f0145 design review 002 F3: a "buy" arrival was sent back to the lobby only by a teleport whose errors were swallowed; when it failed, the player played the whole game unpaid and their score reached the boards.

**How to apply:** stop the thing first (f0145 refuses the run: over at once, no GameOver, nothing submitted), then teleport, and kick with the reason when the teleport errors, fails to start, has no destination or has not taken the player within a bound; pin each failure with a case and "back only asks for a teleport" as a mutant.
