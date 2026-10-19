# Design refute 004

- F1: fixed: the normaliser removes long comments (`--[[ … ]]`, any number of `=`) with their contents before the line-comment strip, so a hidden assertion or loop no longer matches the golden text; mutants M21 (every assertion inside `--[[ … --]]` lines) and M22 (a loop inside `--[=[ … --]=]`) added and run, both fail on an assertion; M1 and M13 re-run, still fail; `promote-check R0036` OK; E3 says what the normaliser tolerates and nothing else; consequences: none (the golden text has no comment in it).
- F2: fixed: c0103's Affected specs quotes the output for the Touched path itself, and c0103 and f0104 no longer say the narrowed spec checks that `View.KEYS` is frozen (`view.spec` does); consequences: none.
