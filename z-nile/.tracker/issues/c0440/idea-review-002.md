# Idea review 002

## Findings

- F1: The solution's first bullet tests the raw command text ("a semicolon or a newline appears anywhere after a cd"), so a reader can't tell whether `cd x && git commit -m "fix; tidy"`, or a here-document body after `cd x && cat > f <<EOF`, is refused. Read literally, both are refused, though every command in them is joined by "&&" and nothing runs in the original folder. That also contradicts the third bullet. The hook already reads a line the way the shell does: `split` in `z-nile/engine/boundcmd.luau:259` ignores separators inside quotes, `withoutHeredocs` at line 1112 removes here-document bodies, and lines 859–875 already track the folder through each `cd`. The rule should therefore name the separators the shell reads between commands, not the characters in the text.

## Verdict

revise
