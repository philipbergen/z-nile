---
title: A tripwire covers every interval, not only the step it wraps
when: design
tags: [security, detection, process]
check: What happens between two checks (after a step, between steps, after the chain), can a process outlive the window it is checked in, and is the last vetted state kept somewhere a later run reads first?
---
A check that compares "before the step" with "after the step" misses everything that happens after it: a detached process (setsid) that pushes later, a stolen credential used between runs. Keep the last vetted state (a watermark) and check from it at the start of every run, before every step and after every step, so no interval is unwatched. Say plainly that this detects after the fact and never prevents.

**Why:** c0117 design review 002 F4: a step left a detached process that pushed code to `main` seconds after the step's tripwire had passed; the next step's "before" was taken after the push, so nothing ever compared across the gap.

**How to apply:** persist the watermark outside the repository; vet every commit since it with the same function the guards use; stop until a human acts; spec a late push caught at the next run.
