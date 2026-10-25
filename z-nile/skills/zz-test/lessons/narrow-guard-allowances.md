---
title: A guard scan allowance is as narrow as the need
when: both
tags: [guards, scans]
check: When a spec needs something a guard scan refuses, does it get the narrowest allowance the scan offers (one name in one file), rather than an exemption from every rule of every scan?
---
`repo-fence.spec` offers two ways past its scans: `EXEMPT` (a whole file skips the guard scan and the identity scan) and `ALLOWED[path]` (named strings only). A file exempted wholesale can later gain a real override or a non-fixture identity and nothing notices.

**Why:** R0047 design review 001 F5: c0127's `reuse.spec` needed only to clear `PICKMAN_TEST_FENCE`, and the first draft put it on `EXEMPT`, which also skipped the identity scan.

**How to apply:** use `ALLOWED[path] = { NAME = "why" }` for each folder the spec lives in (backlog, active, promoted, through `renamed.id`), and give the fixture a `<name>@example.invalid` identity so the identity scan still passes.
