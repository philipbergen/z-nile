---
title: A check must not require an old ledger line to agree with the thing's current state
when: both
tags: [ledgers, records, gate]
check: Can the thing this record describes change after the record is written, and what does this check say then?
---
A ledger line records what was true when it was written. A gate that compares old lines with current state turns red when the state changes for a good reason, and the only fix is to edit finished history. Gate only the line's shape and that its subject exists (or was merged away); compare the content only where the line is written, for the item that writes it, in a command that names that item.

**Why:** c0181 design review 001 F4: a `- codify` harvest line recording "not codifiable" would have been compared with the lesson's state on every gate, so codifying the lesson later, or merging it, turned every gate red.

**How to apply:** for each check over a ledger, list what can change after a line is written (a lesson's state, a finding's fix, an id) and make the check ignore it, or run only for the current item.
