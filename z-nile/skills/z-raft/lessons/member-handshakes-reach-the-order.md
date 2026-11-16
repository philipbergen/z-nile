---
title: A member's pending handshake with another prep is a step in the raft's Order
when: design
tags: [raft, order, handshake]
from: R0068 design review 001 F4
check: Does any member's design say "action for the lead, before X is readied", and does the raft's Order & dependencies carry that step with its escalation?
---
`ready` and the lead follow the raft document, not the members' designs, so a pre-ready action recorded only in a member's design is dropped.

**Why:** R0068 design review 001 F4: c0136 requires a handshake with c0166's prep before it is readied; the first R0068 Order never mentioned it.

**How to apply:** grep each member for "Handshake", "before .* is readied" and "action for the lead"; copy each into Order & dependencies with who acts and what happens if they decline.
