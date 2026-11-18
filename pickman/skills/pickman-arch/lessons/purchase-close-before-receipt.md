---
title: A purchase flow never assumes the screen closes after the receipt
when: design
tags: [purchases, marketplace]
check: What does the design do when PromptProductPurchaseFinished(bought = true) comes before ProcessReceipt, and when the receipt never comes on this server? And what ends the purchase when no close comes at all (a prompt that never showed, a test screen left unanswered)?
---
Roblox does not order `PromptProductPurchaseFinished` and `ProcessReceipt`: the screen can close, bought, before the receipt reaches the server, and a receipt can arrive late or on another server. A flow that releases its hold on any close ends the thing the player just paid for.

**Why:** f0145 design review 001 F2: the continue offer's countdown was released on every close, so a bought continue whose receipt came a step later found the offer over, and the player lost the run they had paid to continue.

**How to apply:** on a close with the purchase made, keep the hold until the receipt or a bounded wait (`Game.RECEIPT_WAIT_TICKS`), keep a later receipt as a credit, and pin both orders and the wait's end with cases.

**No close at all.** f0208 design review 001 F10: only a close ended the portal's purchase, so a prompt Roblox never reported left the card in "complete the purchase" with every press dropped. Bound the purchase itself (`Play.BUY_SECONDS`) and keep a later grant as a held play.

**An answer that grants nothing.** R0118 code review 001 F3 (f0145): in test mode the test screen's confirm cleared the open screen, and a failed write then returned the same answer as "no screen open", so nothing released the countdown the ask had held and the offer froze. A screen's answer that grants nothing (a failed write) ends the hold as a cancel does. The release is keyed on "this answer took this player's open screen", so that a stray answer never releases a hold something else set (a write in flight, a receipt awaited). R0118 final review 001 F2 found the second way an answer grants nothing usable: the grant was written but the write that uses it failed, so the bought continue was held while the countdown stayed frozen. Key the release on what the answer's grant came to (not applied, and no write in flight that will end its own hold), not only on whether the grant was written.
