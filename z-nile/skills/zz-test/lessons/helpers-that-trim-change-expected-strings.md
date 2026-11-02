---
title: A helper that trims output changes the strings a case can expect
when: both
tags: [specs, helpers, outputs]
check: Does any expected string start or end with whitespace that the helper strips (for example `git status --porcelain` through `fixture.git`)?
---
`fixture.git` trims both ends of its output, so ` M path` arrives as `M path`. A case that expects the untrimmed line fails for every implementation, and a sequestered spec cannot be repaired during execution. Compare the trimmed form, or read the untrimmed stdout through `fixture.exec`.

**Why:** c0181 design review 003 F2: an assertion that nothing changed but one file was written with its leading space and could never pass.

**How to apply:** for each helper a case reads output through, read its trim and quoting rules before writing the expected string, and run the case against a stub that does nothing.
