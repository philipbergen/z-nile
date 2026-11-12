---
title: A tripwire covers every interval, not only the step it wraps
when: design
tags: [security, detection, process]
check: What happens between two checks (after a step, between steps, after the chain), can a process outlive the window it is checked in, and is the last vetted state kept somewhere a later run reads first?
---
A check that compares "before the step" with "after the step" misses everything that happens after it: a detached process (setsid) that pushes later, a stolen credential used between runs. During one process, remember the commit of `main` it started from and judge every commit since it, before every step and after every step. Do not keep that commit in a file. Say plainly that this detects after the fact and never prevents. A push that lands after the process's tripwire, or between runs, is GitHub's branch rules and the broker's fast-forward check.

**Why:** c0117 design review 002 F4: a step left a detached process that pushed code to `main` seconds after the step's tripwire had passed; the next step's "before" was taken after the push, so nothing ever compared across the gap.

**How to apply:** during one process, remember the commit of `main` it started from and judge every commit since it, before every step and after every step, with the same function the guards use. Do not keep that commit in a file: a missing file used to refuse every machine that had not run `dispatch vet`. Between runs, a push to `main` is GitHub's branch rules, the broker's fast-forward check, and `done`. A push that lands after this process's tripwire is not seen here.
