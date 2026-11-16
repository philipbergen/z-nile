---
title: A write lint recognizes every assignment form
when: both
tags: [loops, parsers, lint]
check: Which assignment forms does the matcher accept, and does an unrecognized compound operator or typed declaration prove the loop or void its proof?
---
A static check that decides “nothing else writes this variable” must recognize every assignment form of the language: compound operators (`+=`, `-=`, `*=`, `/=`, `//=`, `%=`, `^=`, `..=`) and typed declarations (`local v: T =`, `for v: T =`). An unrecognized form must count as a write, never as proof. Do not count comparisons or a variable used only inside another target's index.

**Why:** R0072 review-001 F1: `loops.find` proved loops containing `i *= 0`, `i %= n`, `i //= 2`, and `local i: number = 0`; each can spin while the lint asks for no review.

**How to apply:** test every operator and typed declaration as a negative case, with comparison expressions, method calls, and `t[i] = i` as positive controls. `z-nile/tests/tooling/loops-writes.spec.luau` holds the regression cases.

**Note (R0072 review 002 F1):** a line-final operator is an assignment too. Stylua wraps a value that does not fit and leaves `name =` at the end of the line. Read that as a write. Ask: does `x =` with nothing after it void the proof, and does a wrapped `local other =` still leave the loop proven?

**Note (R0072 final review 001 F1):** a matcher that lists the forms of a write reads every form nobody listed as a read. Stylua puts a call's argument or a method's receiver on a line of its own, so count the watched name alone on a line, a `table.<fn>(` anywhere before it, and an assignment to the owner of a dotted name as writes. Ask: what does the matcher say when the formatter puts the name on a line of its own?
