---
title: A stand-in command answers only the arguments the design names
when: both
tags: [stand-ins, specs, mutants]
check: Does every stand-in for an external command (a fake `ps`, `git`, `open` on PATH) answer only the exact arguments and the exact target the design specifies, and fail as the real command would for anything else?
---
A stand-in that prints the same answer whatever it is asked lets a wrong call pass: the code can drop a flag, ask about the wrong process or file, or call the command with nothing at all, and the spec still sees the scripted answer.

**Why:** R0047 design review 001 F2: c0127's stand-in `ps` printed an elapsed time for any arguments, so a call that never passed `-p <pid>` still passed every end-to-end case, and with the real `ps` that call would have disabled the fix.

**How to apply:** make the stand-in check its argv against the one call the design names (flags, order and the target id it was set up for) and exit non-zero, as the real tool would, otherwise. Add a mutant row for a wrong argument. Prefer the real tool where the spec can run it: R0047 replaced the stand-in with a reader that works inside the jail.

R0052 code review 009 F1: a fake that answers `gh pr view <n> --json mergeCommit` with a bare sha for any arguments let a call with `-q` (or without it) pass; the real gh prints JSON without `-q`. Answer only the exact call the code makes, with the real output shape, and run the mutant that drops an argument.
