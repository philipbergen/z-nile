# Review 001: R0112 (code mode)
Reviewer: claude-opus-5-5
Inputs: layer R0112/1/c0371 at 55036ff2dd0d12fe94e84998f345c0b1755a1900, `git diff origin/main...HEAD` (merge base 80f476216; origin/main later moved to d88ae59ad with five new check.sh files, which this review read with the layer's `literals` against origin/main's tree: no path reported); c0371.md, its check.sh, acceptance/ (check-paths-homes, touched-from-home, uses-module, watch.txt) and experiments/checkpaths.diff; R0112.md and its check.sh.

What was run: the four specs one at a time (homes 28/28, touched-from-home 4/4, uses-module 1/1, c0120 check-paths 4/4: 37/37); AC5 and AC6's commands by hand (no other check.sh changed; the five zz-test phrases, the z-design phrase and the inputs.tsv line are there); `stylua --check` and `selene` on the module and c0120's spec (clean); probes of `literals` under `z-nile/.cache/review/` through `../zn run --time 60` (deleted after). Not run, as the brief forbids: `z-nile/check.sh` in any mode, E8 and the other experiments, `./zn check c0371` as a whole.

Sequestration: the name-status diff lists one entry, `A z-nile/.tracker/issues/active/c0371/acceptance/watch.txt`. That file is the ticket's watch map, which `./zn finish` alone writes (zz-test, Capture); it is not a change to a check.sh or a spec. No other check.sh or acceptance file changed.

Deviations in the Verification log:
- Type fix: confirmed. `experiments/checkpaths.diff` applies to `git show 46f7d115:z-nile/tests/acceptance/c0120/checkpaths.luau` with no fuzz or offset. The result differs from the committed module only in annotations and casts (`inDq :: boolean`, `name :: string` twice, `(at2 :: any) :: number` twice, `(p :: any) :: number`, `local last: string?`, and the two `gsub` callbacks wrapped in `(...) :: any`). No statement changed.
- Moves commit folded into one: accepted. The layer is one commit after `./zn finish` in any case. c0120's cases still pass through the module (uses-module pins that no scanner is left in the spec). The diff of c0120's spec keeps every case; it changes only the first case's mapping to `lit.path` and `scanFrom`.
- c0225 fixed in its own prep (#487) rather than modelled: accepted. Main's reader reports that shape too, so it is no regression. No rule was added in the raft (the Risks' intent), and this branch edits no other item's check.sh (AC5).

### F1 [high] Rule L silences a loop whose variable is grep's file operand after `-e` / `--regexp`, against Design item 8
Where: `z-nile/tests/acceptance/c0120/checkpaths.luau:395-404` (`matchedUse`, the grep branch)
Evidence: Design item 8 says the variable is matched text "as grep's **pattern** (the first non-option word, or the word after `-e`; **its file operand is a use**)". `matchedUse` returns `operands == 0 or last == "-e" or last == "--regexp"`, and a word after `-e` is never counted as an operand. So in `grep -e PAT "$f"` the file operand `"$f"` is taken for the pattern (0 operands), and the loop's list becomes text. Probe results for `literals`:
- `for f in tests/missing/a.luau; do grep -q -e "needle" "$f" || exit 1; done` returns `{}`;
- `for f in tests/missing/a.luau; do grep -q --regexp needle "$f" || exit 1; done` returns `{}`;
- `for f in tests/a.luau; do grep -e "x" -e "y" "$f"; done` returns `{}`;
- the same loop without `-e`, `for f in tests/a.luau; do grep -l "TODO" "$f"; done`, returns `tests/a.luau@home`, as it should.

A check.sh whose for list names a missing file and greps it with `-e` passes the scan. That is a missing path silenced, through a form the Design names and gives a behaviour for. It is not a listed Known edge. The homes spec has no case with `-e` in front of a file operand: its rule L cases (lines 401-445, 675-683) cover `grep -qF "old rule" "$f"` and `-e`/`--regexp` as the pattern of a plain grep, not in a loop body. So mutants M22/M45/M46 do not reach this branch. `grep -f "$f"` / `-qf "$f"` (a patterns *file*) is silenced the same way. By item 8's wording that word is the "first non-option word", so it is an unlisted fail-open rather than a contradiction.
Critique: the tempting fix is to count the word after `-e` as an operand. That turns `grep -e "$f" x` into a use, the opposite error: it re-reads c0083-style pattern lists as files, and E8 would show gains.
Consequences: once any `-e`/`--regexp` is present, grep has no positional pattern, so every non-option word that is not an `-e` argument is a file. With `-f`/`--file` the next word is a file too. Reading more loop lists as files can only move the reader back toward main's reading (main reads every list word), so E8 can lose fewer literals but cannot gain one against main.
Recommendation: in `matchedUse`'s grep branch, track whether an `-e`/`--regexp` was seen. If one was, the use is text only when it is that option's argument (`last == "-e"` or `"--regexp"`). Otherwise keep `operands == 0`. Treat the argument of `-f`/`--file` (and a bundled `-…f`) as a use. Add cases (the sequestered homes spec cannot take them, so put them in c0120's promoted spec's literal-reader case, this item's Override, or in a new non-acceptance spec with its watch file, and record the deviation):
- `for f in tests/gone.md; do grep -q -e x "$f"; done` reports;
- `for f in tests/gone.md; do grep -q --regexp x "$f"; done` reports;
- `for f in tests/gone.md; do grep -q -e "$f" x; done` stays `{}`;
- `for f in tests/gone.md; do grep -qf "$f" x; done` reports.

Kill the mutant "the `-e` arm ignored". Rerun E8 and the live-tree case; the 17 lost would-be reports must still be exactly the list, and gained 0.

### F2 [medium] A helper call ends at a command substitution inside its own argument, so its later quoted arguments are reported as paths
Where: `checkpaths.luau:526-528` (`broken` counts `(` and a backtick in a word gap as a command break) and `:580-582` (the call ends at `sep[i]`)
Evidence: Design item 4 says a call's quoted arguments are text "until the command ends (`;`, `&&`, `||`, `|`, a closing parenthesis, a line end …)". In bash, a `$(…)` inside an argument does not end the command. The reader ends the call at the `(` of `$(` (and at a backtick), and every later argument is then read. With `has() { grep -qF -- "$2" "$1"; }` defined:
- `has "$(./zn find c0292)/c0292.md" "tests/run is named"` returns `tests/run@home`, and `z-nile/tests/run` does not exist (only `tests/run.luau` does), so the scan reports a correct check;
- `has "$(cat x)" "the \`tests/run\` word"` returns `tests/run@home`;
- `has "$F" "the \`tests/run\` word"` and `has "${F}/x.md" "tests/run is named"` return `{}`.

`"$(./zn find <id>)/…"` is the documented way for a check to name an item file (z-design lesson check-paths-from-the-home), so passing such a path as a helper's first argument is a natural shape. It is not in Known edges, and no homes-spec case puts a substitution in a helper's argument. It is "as main" in that main read these words too, but it is an unlisted way a correct check.sh is reported, under a rule whose whole job is to stop that.
Critique: the tempting fix is to drop `(` from `broken` altogether. That breaks command position for the first word inside every `$(` and subshell, and that position is what echo, helper calls and `for` rely on (the f0221 shape).
Consequences: the call has to remember the `$(` level it began in. Words inside a deeper `$(…)` are a command of their own: a path there (`has "$(cat src/gone.luau)" x`) must still be read, and a helper or echo there still gets command position. The call ends only at a break at its own level.
Recommendation: record the quoting level (or paren depth of `levels`) at the call. Clear `call` only on a separator at that level: `;`, `&&`, `||`, `|`, the `)` that closes the call's own enclosing group, or an uncontinued line end. Keep `sep` as it is for command position. Cases:
- `has "$(./zn find c0001)/c0001.md" "tests/run is named"` gives `{}`;
- `has "$(cat src/gone.luau)" "x"` reports `src/gone.luau`;
- `has "$F" "x" && test -f src/gone.luau` still reports;
- `(has "$F" "x") ; test -f src/gone.luau` still reports.

Rerun E8; the would-be-report losses must stay the 17 listed.

### F3 [medium] Two unlisted heredoc misreadings report a correct check: a `cd "$ZN_ROOT"` in a heredoc body, and `<<` as an arithmetic shift
Where: `checkpaths.luau:163-183` (heredoc start in `quoting`), `:742-772` (the cd rule runs on every line, heredoc bodies included)
Evidence:
- A heredoc body's words are read like commands (as main), but a cd in the body now moves the top-level frame. `cat > "$FX/check.sh" <<'EOF'\ncd "$ZN_ROOT" && ls\nEOF\ntest -f tests/x.luau` returns `tests/x.luau@root`. Bash runs that `test` from the home, and main read it from the home. A z-nile check that writes a fixture script containing a root cd (a natural shape for checks of ac.sh, the runner or check-paths itself) gets every later home path reported "from the repository root".
- `<<` inside `$(( … ))` is taken for a heredoc whose word is the right operand. `n=$(( 1 << 2 ))\nbash -c 'cd "$ZN_ROOT" && test -f z-nile/x.luau'\ntest -f tests/y.luau` returns `tests/y.luau@root`. The same text with `+` in place of `<<` returns `tests/y.luau@home`. The heredoc freezes the quoting until a line `2`, often the end of the file, so the script loses its context and its root cd leaks to the top level.

Known edges names "parentheses in a heredoc body" and "`$((…))` … not followed (as main)". Neither covers a cd in a body or a shift taken for a heredoc. Both outcomes are "reports", not "as main". The design-review-005 ruling ("the list stands") approved a list that does not contain them.
Critique: the tempting fix is to add them to Known edges. That extends a list the user ruled on, so either it goes back to the user or the reader models them. Each model is small.
Consequences: marking heredoc bodies in `quoting` (a `heredoc[i]` flag beside `comment`) lets `literals` skip the cd rule and the frame parentheses on body lines while still reading their words as main does. That also turns the listed "parentheses in a heredoc body mis-push frames" edge into handled; strike it from the list. A heredoc start must not be taken inside an arithmetic level, so `quoting` has to know `$((` from `$(`.
Recommendation: in `quoting`, open no heredoc while inside a `$((`…`))` level (mark `$((` as arithmetic when pushing `levels`), and export a `heredoc` mark for body bytes. In `literals`, skip the root-cd handling, `cd <dir>` and `applyParens` for words and parentheses on heredoc body lines. Cases:
- the heredoc-body cd above reads `tests/x.luau` from the home;
- `$(( 1 << 2 ))` followed by a root-cd script leaves the next top-level path read from the home;
- `cat <<EOF\n(cd "$ZN_ROOT")\nEOF\ntest -f src/gone.luau` reports from the home.

Rerun E8. If the author prefers not to model them: escalate to the user to extend the Known edges list with these two shapes and their outcome (reports).

### F4 [low] Two smaller misreadings: a quoted lone `{` is a brace group, and a grep pattern with text around `$NAME` is a use
Where: `checkpaths.luau:719-731` (`{`/`}` words taken without a quoting test); `:395-404` with `:365` (`matchedUse` splits `"^$f$"` into a word `^` that counts as an operand)
Evidence:
- `f() {\n  cd "$ZN_ROOT"; grep -q "{" x\n}\ntest -f tests/y.luau` returns `tests/y.luau@root`. The quoted `{` is pushed as a group, so the function's `}` pops it and not the function, and the function's root cd survives its body (reports). Without the quoted `{` it is read from the home.
- `for f in tests/a.luau; do grep -q "^$f$" list; done` returns `tests/a.luau@home`. Item 8 calls `$NAME` inside grep's pattern text, but the anchored pattern counts as an operand (as main; it reports, not fails open).

Neither is in Known edges.
Critique / Consequences: requiring `q.dq[abs] == false` and the frame's own context for `{`/`}` changes nothing for real groups. Counting a grep word that contains the use as the pattern (not as an operand) only makes more loop lists text, so check E8's lost list against the 17.
Recommendation: test `not q.dq[abs]` (and `q.comment`) before pushing or popping `funcs`. In `matchedUse`, treat the word that holds the use as the pattern slot when no earlier non-option word was taken. Add one case each (outside the sequestered folder, as in F1), or list both under Known edges with the user.

## Judged criteria (code mode only)
- None: c0371 has no Judged criteria (its `### Judged` says "None."), and R0112 adds none.

Lesson candidates (for the lead to harvest; I write none):
- zz-test (measure-hand-written-readers-on-the-corpus, a note): a rule that names an option's argument as one reading (`-e PAT`) needs a case for the other words of that command too (`-e PAT FILE`), because mutants run only on the cases written. Check: for every option the Design says changes a slot, is there a case where the slot it frees holds the loop variable?
- zz-arch: a reader that ends a construct at a "command break" must say at which nesting level, because a substitution inside an argument is not a break in bash. Check: does each end condition hold inside a `$(…)` that sits in the construct's own argument?

Verdict: changes
