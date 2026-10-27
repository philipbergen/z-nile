---
title: A spend decided before a yielding write is re-checked after it, or given back
when: design
tags: [server, concurrency, purchases, remotes]
check: What happens to a spend when the phase it needs ends, the player leaves, or the same client asks again while its write yields, and does a spec fire those events inside a yielding write?
---
A server that checks a condition, then spends a credit through a store write that yields, can find the condition gone when the write returns: the player declined, left, or asked again. Applying the spend then wastes it or revives something that has ended; asking again starts a second spend.

**Why:** f0145 design review 002 F2: the play place checked the offer, then used a held continue through `UpdateAsync`; a second ask during the write spent two continues for one, a decline during it spent one for nothing, a leave during a receipt's write revived a parked run so its hiscore was never submitted, and twenty asks made twenty writes. Synchronous stubs showed none of it.

**How to apply:** keep one in-flight marker per player (asks meanwhile dropped, a decline noted and applied after), re-check the player, the session and the phase once the write is back, and give the credit back (idempotently, keyed by the use) when the check fails. Give the stub a hook that fires events inside a write, and run the "no guard", "no re-check" and "no refund" mutants. Extends zz-arch/client-triggered-reads-guarded from reads to spends.
