---
title: An option that fills one argument slot moves every slot after it, and each move needs a case
when: both
tags: [scanners, shell, grep, cases]
check: For every option the design says changes which argument is the pattern (`-e PAT`, `--regexp PAT`, `-f FILE`), is there a case where the slot it frees holds the thing under test (the file operand after `-e PAT`), and not only a case where the option's own argument does?
---
A reader that decides what a word is by counting the operands before it must say what each option does to the count. `grep PAT FILE` and `grep -e PAT FILE` put the file in different positions: after `-e PAT` the first operand is already the file.

**Why:** R0112 code review 001 F1 (high): c0371's rule L counted "no operand before the use" as "the use is grep's pattern". With `grep -q -e "needle" "$f"` no operand precedes `$f`, so the loop's list was read as text and a missing path was silenced; `grep -qf "$f"` (a patterns file) the same. The design said the file operand is a use, and the homes spec had cases for `-e "$f"` as a pattern but none for `-e PAT "$f"`.

**How to apply:** for each option that takes the slot under test, write both cases: the option's argument is the thing (`-e "$f"`: a pattern), and the option is given elsewhere so the next operand is something else (`-e PAT "$f"`: a file). Add a mutant that drops the "a pattern was already given" state.

Every spelling of the option needs the case, not only the spaced one: R0112 final review 001 F3 found the fix above reading `-e PAT` and `--regexp PAT` but not the glued `--regexp=PAT`, `-ePAT` and `--file=FILE` (deferred to c0382). The same review's F2 is the neighbouring gap: where two clauses of one rule apply at once (an echo with an option and a one-word message), a case must hold both, because the code tested the word before the message instead of the message.
