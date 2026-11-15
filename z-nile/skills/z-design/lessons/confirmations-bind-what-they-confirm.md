---
title: A recorded confirmation names what it covered and goes when that changes
when: design
tags: [confirmation, approval, record]
check: Can the thing a recorded confirmation or approval covers change after it was given without the confirmation going, and which command, land or claim refuses a confirmation that no longer matches?
---
A line that says "the user confirmed" is true only of the text the user saw. If the record or the idea can grow after the line, the line vouches for words nobody confirmed.

**Why:** c0260 design review 009 F4: a message recorded after the last round, or a hand edit of the Problem after `--confirm`, left the `Confirmed` line standing, and the claim and the audit accepted it.

**How to apply:** each round records what it was given (counts of the user's messages and questions, a hash of the idea) where the engine writes it; the confirmation is refused when that no longer matches, and a record or a round after it drops the line. Check it where the item is still an unclaimed capture, so later design edits do not void it.
