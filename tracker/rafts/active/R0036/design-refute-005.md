# Design refute 005

- F1: fixed: the normaliser no longer strips comments. The only tolerances are whitespace, a trailing comma before `}` and masked item ids; the narrowed spec's four header lines are in the golden text, so no code can hide in a line comment, a long comment or a string. Mutants run, all fail on an assertion: a loop inside `--[[ … --]]` (M21), a case name that is a string opening a long comment (M22), a line comment opening one (M23), an early `do return` (M24); M1, M13 and M18 re-run; a one-line `want` table and a renamed id still pass; `stylua --check` clean; `promote-check R0036` OK; consequences: a later edit to the narrowed `keys.spec` header must update the golden text (the narrowed.spec header says so).

This was the final round (5) and it held a high, so per ticket-prep step 4 it goes to the user; the fix is applied but R0036 is not marked ready.
