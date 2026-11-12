---
title: A state exempted from a guard because another check "already ran" there must actually run that check
when: design
tags: [guard, exemption, review]
check: For each "X is exempt from this guard because Y already decided it", does Y really run in that state, or is Y skipped by a condition the exemption itself creates?
---
Two exemptions can stack until nothing guards the path.

**Why:** c0256 design review 004 F1: round 3 exempted a capture that stopped with a question from the made-twice guard because "z-ticket was judged and made nothing", but the judgement (the check that z-ticket made no issue) is skipped exactly when `questions.md` exists, so a z-ticket that made an issue and then asked was captured a second time at the retry.

**How to apply:** write the exemption with the check it relies on and walk that check's own conditions for the exempted state; if the check is skipped there, run it there, or fail the state it cannot judge, and pin the sequence with a case.
