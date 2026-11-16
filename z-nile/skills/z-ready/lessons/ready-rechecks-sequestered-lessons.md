---
title: Re-ready sequestered files against newer lessons
when: both
tags: [ready, review, specs]
check: Which lessons landed between each member's prep and this ready, and does any sequestered file repeat one of their defects?
---
Preparing a raft is also a freshness review of its members' sequestered specs and checks. Search the lessons that landed after each member's design review and apply them to those files, not only to its prose. A conflict the executor may not edit must reach the human before implementation.

**Why:** R0072 review-001 F2: c0193 was prepped before zz-test/specs-never-burn-real-resources landed, so its sequestered spec carried two real 3-second spinners into execution, where the author could not change them.

**How to apply:** compare prep and ready dates, search the intervening lessons, and read every matching sequestered case again. Re-prep or escalate a conflict; never solve it by editing the file during execution.
