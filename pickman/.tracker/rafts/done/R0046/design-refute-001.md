# R0046 design refute 001

- F1: fixed: the hook case now scans `src/server` for `[%.:]again%s*%(`, `%.again%s*=` and `%[%s*"again"%s*%]`; the Design bullet, AC1, the case label and the Rules and mutants row name the four forms. consequences: three new mutants (M4b colon call, M4c assignment, M4d brackets) were run on `proto-c0129` and each fails the case; a `Session.playAgain` reference does not (no false red). No new rule, state or interface.
- F2: fixed: the case collects the matching paths and asserts `table.concat(found, ", ")` is `""`, so a failure prints the file (on main: `expected "", got "Submits.luau"`). consequences: none.
