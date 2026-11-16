---
title: A reply built from a shared cache still carries each player's own figures, and says when one is not known yet
when: design
tags: [cache, server, players]
check: For each reply built from rows a server shares among players (a snapshot, a cache), what does each per-player field (the player's rank, their best) say for a player who asks at every phase of the cache's cycle (just after a refresh, inside the read window, after it, just before the next), is "not known yet" told apart from "none" in the reply, the client and the view, does the client ask again sooner while it is not known, and is a per-player figure tied to the rows it was heard with rather than to the time of the last refresh?
---
A shared snapshot answers many players from one read, but the player's own rank and best come only from a read made for that player. A rule that forwards a player's ask only while the shared cache is fresh leaves every player whose asks fall outside that window with whatever was last heard for them, which for a newcomer is nothing, drawn as "no best"; and a per-player mark dropped on every refresh blinks although the rows did not change.

**Why:** f0206 design review 001 F1 and F2: a player asking 20 s after another player's refresh, every 30 s, was answered from the portal's snapshot forever, so the board showed `YOUR BEST — — —` (the design's "no run") for a player with runs; and the player's own row lost its mark on every snapshot answer after someone else's refresh.

**How to apply:** keep per player whether their own figure has been heard; until then the reply carries a pending value (`false` beside nil), the client draws a pending mark and asks again at its short retry, and the next ask inside a read window (or the player's own refresh) fetches it. Tie a held rank to a version of the rows that only changes when the rows do. Prove it with a case that brings players in at every phase of the cycle at the screen's own cadence and bounds when each sees their own figure.
