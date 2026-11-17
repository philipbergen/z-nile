---
title: A server that tells the client its mode tells it on every path that lets the player through
when: both
tags: [purchases, fail-safe, client-defaults]
check: For each path that lets a player play or buy (each fail-safe that lets a store failure through included), what does the client's price or mode line say there, and is there a case where the client has heard nothing on a live server?
---
A client screen shows a default until the server reports, and a paid-play client's safe-looking default is "test: nothing is charged". A server that reports only after a successful read or write leaves that default up on exactly the paths a fail-safe keeps open on purpose. On a live server the screen then says nothing is charged while a press opens the real purchase dialog.

**Why:** R0118 code review 001 F1 (f0145): Continues told PayStatus only when the arrival's write gave a record. A live player whose write failed (G10 lets them play) reached the continue offer with "1 ROBUX (TEST: NOTHING IS CHARGED)", and CONTINUE prompted the real Developer Product. A continue granted outside the offer was never told either, so a later offer showed the price while one was held.

**How to apply:** tell the mode on every verdict that lets the player through, with an empty status when the record is unknown (the client reads it as nothing held, so live shows the price and closed shows the store unavailable). Tell again after every record the server writes or hears: a purchase, a use, a give-back. Pin the fail-safe path with a case on a live stub whose store fails, not only the success paths.
