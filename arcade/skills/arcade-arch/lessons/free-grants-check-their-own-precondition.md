---
title: A library call that gives something free checks its own precondition
when: design
tags: [library, api, payments, authority]
check: For each library call that grants something without payment (a pass, a free start, a credit), does the call itself check the condition the user's rule names (a failed read, a due hour), rather than trusting the place to call it only then, and do cases show it refusing after each other outcome (a good read, a busy one, a second call)?
---
"The place calls it only when the read failed" is a rule every consumer must get right, and the easy mistake (treating every nil as a failure) hands out free games. The library knows what its last read answered, so it can refuse.

**Why:** f0201 design review 001 F7: `Wallet.pass` wrote a pass whenever it was called, and `read` answers nil both for "busy" and for "down"; a portal that passed on any nil would give a double-pressing client a pass on its second press, and the buy arrival would play free.

**How to apply:** keep the outcome of the last call per player and title, let the free grant through only after the outcome the rule names, once per such outcome, and add cases for each refusal and a mutant "unconditional".

**Also:** R0110 code review 001 F2: `Wallet.pass` honoured a "down" that was no longer the last answer: after it, a busy answer or an answer from the record seen left the allowance set, and `pass` wrote. The outcome the rule names must be the last one: every other answer since clears it, with a case for each answer that follows a down.
