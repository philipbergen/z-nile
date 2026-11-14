---
title: A retired signal fails loud
when: design
tags: [signals, dispatcher, migration]
check: When a design retires a signal (a file a step writes to stop the chain), what happens when a step still produces it, and does that stop the run with a message naming the new signal, rather than being ignored or re-run?
---
A step that follows an old habit or an older skill copy still writes the old signal. Ignoring it quietly re-runs the step, and the person cannot answer it any more.

**Why:** c0250 design review 001 F10: an item's `questions.md` stopped nothing after the change, so the chain re-ran the step up to 30 times, and `retry --answer` was refused for an item.

**How to apply:** treat the retired signal as a failure that names its replacement, set it aside so a retry runs clean, and pin both with cases.
