---
title: Every flag value and mode pair a rule states has a case, and the prototype is read against the rule
when: design
tags: [flags, modes, prototype]
check: For each rule that names a flag value or a mode combination (a value that means "no change", a flag beside another mode), does a spec case run that exact combination against the bare behaviour in every mode the rule covers, and does the prototype's code, not only its design text, satisfy the rule?
---
A rule stated in the Design ("`all` is the bare gate") is easy to break in the prototype for the modes nobody ran, and the executor copies the prototype.

**Why:** c0083 design review 001 F6: the prototype's `--suite all` skipped the static narrowing, so `--affected --suite all` ran every project's static stages where the bare gate ran only the changed ones; the one case compared plans under `--full`, which hid it. `--slow` beside `--suite` was undefined, and the usage line and the skill disagreed about it.

**How to apply:** make the no-op value a no-op by construction (parse it away), run each mode (`--plan` with each of `--full`, `--affected`, `--static`) against the bare output with a stub that makes narrowing visible, and refuse or define every other mode in the rule, the usage text and the skill together.

**Note** (c0462 design review 001 F6, F10): a rule that holds in every project home needs a case from a second home (a `HOME == "z-nile"` mutant passed every spec), and a flag passed to workers by two code branches needs one builder or a case per branch.
