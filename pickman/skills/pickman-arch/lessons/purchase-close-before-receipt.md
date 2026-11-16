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
