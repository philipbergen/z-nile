---
title: A guard's own state is out of reach of what it guards, or checked against a copy that is
when: design
tags: [security, detection, state]
check: Can the guarded process delete or rewrite the guard's record (a file, a config entry, a remote URL), who else legitimately writes that record, and what does the guard do when it is missing or changed: trust it, stop, or re-check what it guards from its own copy?
---
A watermark file the step can delete, read back after the step, turns one `rm` into a quiet tripwire; a remote URL read from the shared git configuration lets the step point every later check at a frozen copy. Hold the guard's state in the guard's own memory for the process. A missing file must not refuse the next run: that rule stopped every machine that had not written one. Pin origin's URL for the process and compare the configuration after each step. Where the same OS user can still rewrite configuration between runs, say so as a known limit.

**Why:** c0117 design review 003 F2 and F3: a step deleted the watermark and pushed code past the wrapper; another repointed `remote.origin.url` at a frozen copy; both tripwires stayed quiet.

**How to apply:** hold the mark and origin's URL in memory for the process, and compare the configuration after each step. Do not persist either. A missing file must not refuse the next run. Spec a repointed origin during a step.
