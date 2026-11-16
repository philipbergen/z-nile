---
title: A helper that trims output changes the strings a case can expect
when: both
tags: [specs, helpers, outputs]
check: Does any expected string start or end with whitespace that the helper strips (for example `git status --porcelain` through `fixture.git`)?
---
`fixture.git` trims both ends of its output, so ` M path` arrives as `M path`. A case that expects the untrimmed line fails for every implementation, and a sequestered spec cannot be repaired during execution. Compare the trimmed form, or read the untrimmed stdout through `fixture.exec`.

**Why:** c0181 design review 003 F2: an assertion that nothing changed but one file was written with its leading space and could never pass.

**How to apply:** for each helper a case reads output through, read its trim and quoting rules before writing the expected string, and run the case against a stub that does nothing.

c0239 design review 001 F6: the same gap one step earlier. A sequestered spec borrowed c0165's `gatefix` helpers without reading them: `gatefix.specs` always wraps `specs -- run --project pickman` (so a `digest` or `scope` call went to the wrong subcommand) and `gatefix.sql` trims its output (so `toBe("1\n")` could never match). Open the helper, write down its wrapped command, arguments and return shape next to each call in the spec, and run one case against a stub before the review.
