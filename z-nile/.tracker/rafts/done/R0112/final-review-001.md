# Review 001: R0112 (final mode)
Reviewer: claude-fable-5-2
Inputs: the stack at 84d3cafb5 (layer R0112/1/c0371, finish commit b7a33e86aa8274bd1bec1ed9f0ffac4db907ab35, then two tracker-only commits); `git diff origin/main...HEAD` (merge base e6e1e28ab); `./zn capture c0371` (capture efa610174, no marker); c0371.md, its check.sh, acceptance/ (check-paths-homes, touched-from-home, uses-module, watch.txt) and results.txt; R0112.md, its check.sh, review-001.md and refute-001.md; the committed trace skeleton.

What was run: the five specs one at a time (homes 28/28, touched-from-home 4/4, uses-module 1/1, c0120 check-paths 4/4, tooling checkpaths-review 4/4: 41/41); probes of `literals` under `z-nile/.cache/review/` through `../zn run --time 60` (deleted after); `experiments/checkpaths.diff` applied to `git show 46f7d115:z-nile/tests/acceptance/c0120/checkpaths.luau` in a scratch folder and compared with the committed module; `./zn trace R0112 --check`. Not run, as the brief forbids: `z-nile/check.sh` in any mode, `./zn check c0371` as a whole, E8 and the other experiments, stylua and selene.

Idea = design = test = code, my own reading before the code review's:
- The capture has a Problem and a template Solution, so the claims are P1 and the criteria. Its three misreadings each have a numbered Design rule (the Touched comparison, rule R, rule H), a homes or touched-from-home case and code. The fourth (rule E) and the fifth (rule L, c0193) were found in prep and are recorded as such. The Problem's four `Scope decision` lines only add detail; no captured outcome is dropped or moved to Non-goals.
- "A missing path is still caught" holds for every form I probed that the Design models, with the exceptions in F2 to F4 below.
- "Main's full gate is green again" has no check in this stack. The Design says so (the line under AC6) and the raft leaves it to the one `--full` at the merge. RC1 and AC4 prove the red spec alone.
- The diff holds nothing extra: the module, c0120's spec (its scanner removed, the first case mapped to `lit.path`, `scanFrom`), the two skill sentences, one `inputs.tsv` line, the tooling spec with its watch file, the ticket's `watch.txt` (written by `./zn finish`), three lesson files and tracker records. No `check.sh` and no acceptance spec changed.

The Verification log's deviations:
- Types: confirmed by my own diff. The prototype module with `experiments/checkpaths.diff` applied differs from the committed module only in annotations and casts (`inDq :: boolean`, `name :: string` twice, `(at2 :: any) :: number` twice, `(p :: any) :: number`, `local last: string?`, the two `gsub` callbacks cast to `any`) and in the F1 fix at lines 396 to 414. No other statement changed.
- c0225 fixed in its own PR #487: accepted. Main's reader reports that shape too, the raft's Risks call a new shape a stop and not a new rule, and AC5 holds.
- The moves commit folded in: accepted. `./zn finish` leaves one commit in any case, and uses-module pins that the spec keeps no scanner.

The code review's answers:
- F1 (fixed b7a33e86a): the fix is real for the forms the finding named. `grep -q -e "needle" "$f"`, `--regexp "needle" "$f"`, `-e one -e two "$f"`, `-qf "$f"`, `-f "$f"` and `--file "$f"` now read the list, and the pattern forms stay text. The spec is a real proof: review 001's probes show two of its cases returned `{}` before the fix, it has negative cases, and it asserts on `literals`' output. The fix does not cover the glued spellings (F3 below).
- F2 (deferred c0381): legitimate. The outcome is a report of a correct check, main reads the shape the same way, and no corpus file has it. Medium is the right severity.
- F3 (deferred c0381): legitimate, with one correction to the refutation's wording. A root cd in a heredoc body also fails open for a later path that exists from the root and not from the home, not only "reports". c0381's Problem states the cause (the later home path is read from the root), which covers both. It is unlisted and absent from the corpus, the same class as the listed backtick edge, so it is no disguised high.
- F4 (deferred c0381): legitimate, low.

The tooling spec and the trace: `z-nile/tests/tooling/checkpaths-review.spec.luau` is outside the ticket's `acceptance/` folder. The tool takes it as a spec of the ticket all the same (`z-nile/engine/trace.luau:889`, any spec under the home's `tests/` that is not another item's acceptance folder), and its four cases are green in `results.txt` (lines 187 to 191). A `test` cell may cite it. No row of this table needs it, so none does. c0120's own spec is the reverse: `results.txt` records it green, but the tool refuses it as another item's acceptance spec, so AC4's cell cites `check.sh:21`.

The trace's artefact rows: AC7 and AC8 are the "None." paragraphs under Judged and Observed, which the tool derives as claims. Their cells name the "None." line, the `finish` line and line 1 of the module, and say they prove nothing, as R0103's and R0109's tables do. AC5's `code` cell is nominal for the same reason: it is a property of the diff.

The skill sentences and the `inputs.tsv` line: the zz-test sentence matches the code (a root cd holds to the end of its subshell, substitution, script or function body, and a top-level cd holds for later scripts, `stackOf` at checkpaths.luau:469; helpers, code spans, echo and printf in command position, the text-only `for` list). The z-design bullet states `owned`'s rule (checkpaths.luau:40). The `inputs.tsv` line names the homes spec at the path it has after promotion, with `*`, which its live case needs.

### F1 [high] `./zn trace R0112 --check` does not pass: `origin/main` moved during the review
Where: `z-nile/.tracker/rafts/active/R0112/trace.md` (the `Commit:` line and every cell that cites `check.sh`)
Evidence: the check printed, with every cell filled:
```
row Commit, commit: table is stale (R0112/1/c0371 is not stacked on the layer below)
row c0371:P1, test: z-nile/.tracker/issues/active/c0371/check.sh:21 did not run green for this stack
row c0371:AC1, test: z-nile/.tracker/issues/active/c0371/check.sh:12 did not run green for this stack
row c0371:AC2, test: z-nile/.tracker/issues/active/c0371/check.sh:15 did not run green for this stack
row c0371:AC3, test: z-nile/.tracker/issues/active/c0371/check.sh:18 did not run green for this stack
row c0371:AC4, test: z-nile/.tracker/issues/active/c0371/check.sh:21 did not run green for this stack
row c0371:AC5, test: z-nile/.tracker/issues/active/c0371/check.sh:24 did not run green for this stack
row c0371:AC6, test: z-nile/.tracker/issues/active/c0371/check.sh:30 did not run green for this stack
row c0371:AC7, test: z-nile/.tracker/issues/active/c0371/check.sh:38 did not run green for this stack
row c0371:AC8, test: z-nile/.tracker/issues/active/c0371/check.sh:38 did not run green for this stack
```
These ten lines are one cause. The layer's base is e6e1e28ab, and `origin/main` went to a5462d413 ("tracker: spend c0380 capture (#492)") while this review ran; the command fetches. No line names a commit after the table, and no line complains about a design cell, a spec case, a code cell or a source-file row.
Critique: the tempting fix is to edit cells. No cell is wrong.
Consequences: the restack gives the layer a new finish commit, so `Commit:` changes, and the line numbers must be checked again on that commit (they hold unless the restack changes c0371.md, check.sh, the three specs, the module or `inputs.tsv`; `inputs.tsv` is shared, and a line added above 299 by main moves the two cells that cite it).
Recommendation: restack the layer on `origin/main`, rerun the live-tree case as the raft's Risks require, set `Commit:` to the new finish commit, correct `z-nile/tests/inputs.tsv:299` if it moved, and run `./zn trace R0112 --check` again.
Lesson: zz-review/not-stacked-is-main-moving

### F2 [medium] A one-word echo or printf message after an option is silenced, against Design rule 7
Where: `z-nile/tests/acceptance/c0120/checkpaths.luau:665-667` (the one-word test needs the word right before to be `echo` or `printf`), with `:621-629` (the message is the first word after the options)
Evidence: rule 7 (c0371.md:62) says the message is "the first argument after options" and that "a message of one word is a value and is read". `literals` returns:
- `x=$(echo tests/gone/x.luau)` gives `tests/gone/x.luau`;
- `x=$(echo -n tests/gone/x.luau)` gives `{}`;
- `x=$(echo -n "tests/gone/x.luau")` gives `{}`;
- `x=$(echo -e "tests/gone/x.luau")` gives `{}`;
- `x=$(printf -- tests/gone/x.luau)` gives `{}`.

Main's reader reads all five. A check that returns a path with `echo -n` passes the scan when the path is missing. It is not a Known edge. The homes spec pins the one-word value without an option (lines 452 and 455) and the several-word message with one (line 454), never the one-word message with an option. None of the 472 tracked check.sh files has the shape.
Critique: the tempting fix is to skip option words backwards from the message. That would also take `grep -c echo "tests/x"`-like word orders for an echo.
Consequences: the marking pass already knows which word is a message in command position (`message[i]`, line 628). Using that mark in place of the word before changes nothing for a message without options, and only un-silences words main reads, so E8 cannot gain a report against main.
Recommendation: at line 667 test `message[i]` and drop the `before` comparison. Cases, outside the sequestered folder as F1 of the code review did (the tooling spec): `x=$(echo -n tests/gone/x.luau)` and `x=$(printf -- "tests/gone/x.luau")` are read, `echo -n "src/nothing is gone"` stays `{}`. Rerun E8: 0 gained, the 17 listed losses. Or defer to c0381 with the shape added to its Problem.

### F3 [medium] The fix of code review F1 misses the glued spellings of the same options
Where: `z-nile/tests/acceptance/c0120/checkpaths.luau:400-414`; `z-nile/tests/tooling/checkpaths-review.spec.luau:18-36` (only the spaced spellings)
Evidence: Design rule 8 (c0371.md:63) says grep's file operand is a use. `literals` returns:
- `for f in tests/missing/a.luau; do grep -q --regexp=needle "$f"; done` gives `{}`;
- `for f in tests/missing/a.luau; do grep -q -eneedle "$f"; done` gives `{}`;
- `for f in tests/missing/a.luau; do grep -q --file="$f" out.txt; done` gives `{}`;
- `for f in tests/missing/a.luau; do grep -q --regexp="needle" "$f"; done` gives `tests/missing/a.luau`, only because the quote splits the word and `needle` is counted as an operand.

`--regexp=PAT` and `-ePAT` are one word that starts with `-`, so `given` stays false and the file operand is taken for the pattern; `--file=` is not `--file`. Each is the fail-open the code review rated high, in a spelling its recommendation did not list. None of the 472 tracked check.sh files has one.
Critique: the tempting fix is one more string comparison per spelling. The next spelling (`-qe`, `-Fe`) then reads right only by accident, as `grep -qFe "needle" "$f"` does today.
Consequences: one rule for the three shapes keeps it small: a word `--regexp=<text>` or `-<letters>e<text>` gives the pattern; a last word `--regexp=` or a short group ending in `e` makes the use the pattern; a last word `--file=` or a short group ending in `f` makes it a patterns file. Each change reads more lists as files, toward main's reading, so E8 cannot gain a report.
Recommendation: apply that rule in `matchedUse`'s grep branch and add the four lines above as cases of the tooling spec, with `grep -q --regexp="$f" "$DOC"` and `grep -qe "$f" "$DOC"` staying `{}`. Rerun E8. Or defer to c0381 with the spellings added to its Problem.

### F4 [low] Rule L finds a use in a longer variable name and in a comment
Where: `z-nile/tests/acceptance/c0120/checkpaths.luau:441-453` (a plain search for `$NAME` in the body)
Evidence: rule 8 says "a loop that never uses its variable is read as files". `for f in tests/missing/a.luau; do grep -q "$fx" "$DOC"; done` gives `{}`: `$fx` is taken for `$f`, a matched use. `for f in tests/missing/a.luau; do\n  true # case *"$f"*\ndone` gives `{}`: the use is in a comment. With `$files` as the pattern and `"$f"` as the file the list is read, so the miss needs a loop that never truly uses its variable. The homes spec pins that rule with a body that has no `$` (line 428).
Critique / Consequences: requiring that the byte after the name is no word byte, and skipping bytes the quoting pass marks as a comment, changes nothing for a real use.
Recommendation: add both tests in `textOnlyLoop` with one case each, in c0381.

Lesson candidates (for the lead; I write none):
- zz-test/an-option-that-gives-the-pattern-moves-the-file-operand, a note: a fix that names an option covers each spelling of it (`-e PAT`, `-ePAT`, `--regexp PAT`, `--regexp=PAT`, a short group ending in the letter), because R0112's final review found the fix of code review F1 open for the glued ones. Check: for each option the fix names, is there a case per spelling?
- z-design/spec-design-correspondence, a note: a rule with two clauses ("after options", "one word is a value") needs a case where both apply at once (R0112 final review F2).

Verdict: changes
