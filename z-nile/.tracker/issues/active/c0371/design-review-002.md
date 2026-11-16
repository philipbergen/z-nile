# Review 002: c0371 (design mode)
Inputs: prep worktree `prep-check-paths-homes` at 73486845e. Read:
- c0371's c0371.md, check.sh, `acceptance/check-paths-homes.spec.luau`, `experiments/checkpaths.diff`, the E5 and E7 probes, design-review-001.md, design-refute-001.md and harvest.md;
- the two new zz-test lessons;
- `./zn capture c0371` (efa610174);
- c0141 at the same commit (c0141.md, check.sh, both acceptance specs) and its prototype 46f7d115;
- the live and finished check.sh files of all seven projects: 240 unfinished, 223 finished.

How I ran it:
- A scratch clone of the worktree, merged with origin/main 9fc032c2c, its remote pointed at nothing.
- The prototype is `final-checkpaths.luau` plus `final-spec.luau`. `patch` confirms the module is 46f7d115's module plus `checkpaths.diff`. c0141's specs went under `tests/acceptance/c0141/` and c0371's under `tests/acceptance/c0371/`.
- On it, c0371's spec passes 9/9, c0120's check-paths spec 4/4 (live case included), and c0141's specs 4/4 and 1/1. stylua and selene are clean on c0371's folder and on the module.
- Every probe ran under `./zn run --time`. The probes are in the clone's `z-nile/.cache/r2/`:
  - `diff.luau`: literals, c0141 vs c0371, for every check.sh;
  - `cases.luau` with `cases1-4.txt`: c0371's spec fixture, run over hand-written cases with either module;
  - `apos.luau`: literals with and without the apostrophes in comments;
  - `q.luau`: the quoting state at a line.
- The mutant runner is the scratchpad's `r2-mut.sh`. It runs c0371's spec with its live case removed (`nolive.spec.luau`), then c0120's spec.

Most of round 1 is answered:
- F1 (c0141's reading and rule L), F3 (the user's full-scope ruling), F7 (c0141's uses-module pin) and F8 (c0374) are real.
- The cross-line root reading of F2 works for the pinned shapes.
- The answers that are not true are F6, F10 and F13 (F9 below), and part of F2 (F3 below).

The new machinery has three defects that the live tree hides, because they cancel each other out on c0292 (F1, F2 and F3 below). The rules added in this round have gaps of their own (F4 to F7). The c0141 arrangement leaves c0141's layer unspecified (F8).

### F1 [high] The quoting pass reads comments, so an apostrophe in a comment flips every quote context after it. That is the template's line 6 "its project's", in 198 of the 240 live check.sh files
Where: Design item 2 (`quoting(text)`); `quoting` in `experiments/checkpaths.diff`; c0371.md Non-goal 3.
Evidence:
- `quoting` has no comment rule. The word loop skips comment lines and ` # ` tails, but the pass reads them as shell, so `'` in `# … its project's …` opens a single-quoted context. That context lasts to the next `'` of the file, usually the opening quote of the first `bash -c '…'`, which the pass takes as the close.
  - 235 of the 240 live check.sh files have an apostrophe in a comment.
  - 198 have the template's line 6, "promoted to its project's tests/acceptance/<id>".
- **A regression against main.** z-nile item, template line 6, then `check "AC1: the item's files" git diff --quiet -- default.project.json`:
  - c0141's module, which keeps main's per-line quote count, reports `default.project.json (from z-nile)`.
  - c0371's reports nothing. With the apostrophes removed it reports again.
  - The label's apostrophe "closes" the inverted context, and the label's closing `"` then leaves the pass inside double quotes. A FILES word in double quotes is taken as a message.
  - The finished corpus has three real cases of this alone (`apos.luau`): R0034 line 33 `lobby.project.json`, c0058 `.luaurc` and c0076 `.luaurc` twice.
  - This contradicts Non-goal 3 ("c0120 AC11 keeps reporting every case it reports today") and the capture's "a missing path is still caught".
- **A missed report through rule R.** `# the item's check`, then `check "AC1: the item's diff" true`, then `(cd "$ZN_ROOT" && true); test -f z-nile/roots.luau`:
  - nothing is reported. Bash runs the test from z-nile/, where `z-nile/z-nile/roots.luau` is missing, and c0141's module reports it.
  - The `(` and `)` are taken as inside double quotes, so the group never closes.
  - The same happens through template line 6 and a `bash -c '(cd "$ZN_ROOT" && true); test -f z-nile/roots.luau'` script.
- **The live tree passes by accident.** In c0292 (line 8: "the item's project home"), the pass reads line 67's `(cd "$ZN_ROOT" && …)` at context 0 with double quotes on (`q.luau`). In fact it is inside AC6's single-quoted script: with the comment apostrophes removed, it reads context 15 with no double quotes. All 240 live files read the same either way today, but only because the inversions cancel (see F2).
- The code also lets a backslash escape the next byte inside single quotes, where the outer shell ends the string at `'`. Its own comment says "outside single quotes".

Critique: every rule this round adds reads this state: R's group and script ends, H's quoted-argument test, FILES' double-quote rule, and `$(` inside double quotes. The tempting fix is to drop `#` lines before the pass.
Consequences:
- A `#` that does not begin a word must not start a comment: `${#x}`, `$#`, `x#y`, `"#"`, `'#'`.
- Inside a `bash -c '…'` script the outer shell sees no comment, and an apostrophe there really ends the script, so the comment rule applies only at the top level, outside double quotes.
- Inside a script a backslash must still escape `\"` for the script's own double quotes (c0292's `\"\$d\"`), but never a `'`.

Recommendation:
- In `quoting`, a `#` that begins a word, at context 0 and outside double quotes, runs to the end of the line and changes no state.
- A backslash never escapes a `'` inside a single-quoted context.
- I prototyped the comment rule (7 lines) together with F2's fix: c0120's spec 4/4 (live included), c0141's 5/5 and c0371's 9/9 pass, and all three probes above report.
- Cases:
  - template line 6, a label with an apostrophe and `git diff --quiet -- default.project.json`: reported;
  - a comment apostrophe, then a root group that closes by its paren and a home path after it: reported from the home;
  - `n=${#x}; test -f src/gone.luau`: still reported.
- One Rules row, mutant "the pass reads comments". Re-run E5 afterwards.

Lesson: zz-test/shell-readers-carry-state-across-lines. Its How to apply says "keep the quoting of the whole text" and should say that a comment is not quoting.

### F2 [high] A `)` at the end of a line is never counted, so a root-cd group or command substitution that closes at its line end keeps the root reading on for every later line
Where: Design rule 3 (a); the paren scan in `literals`: `for k = (if i == 1 then 1 else ends[i - 1] + 1), s - 1`.
Evidence:
- Parens are scanned only in the gap before each word. The bytes after a line's last word, and a line with no word, are never scanned.
- In a z-nile item with no Touched entries, each of these is silent with c0371's module and reported as `z-nile/roots.luau (from z-nile)` by c0141's:
  - `(cd "$ZN_ROOT" && true)` on one line and `test -f z-nile/roots.luau` on the next;
  - `d=$(cd "$ZN_ROOT" && ./zn find c0001)`, then the same test;
  - the same inside a `bash -c '…'` script;
  - `d="$(cd "$ZN_ROOT" && pwd)"`, then the same test;
  - `(` alone on a line, then the cd and the test, then `)` alone on a line.
- Bash runs every one of these tests from z-nile/. The opposite case, a path present in the home but missing at the root, becomes a false report.
- Five live lines have this shape: c0270:69, c0272:71 and :105, c0294:142, c0316:21. They pass only because nothing later in their function names a path whose two readings differ.
- **With only this fixed, the live case goes red** on `z-nile/.tracker/issues/c0292/check.sh: tests/run.luau (from the repository root)`:
  - F1 puts c0292's line 67 group in double quotes, where its `)` counts only against a leftover `$(` tally.
  - Fixing the line ends changes that tally, so line 68 is read from the root.
  - With F1 and F2 both fixed, the live case passes. The current green result needs both defects at once.
- No case has a `)` at a line end followed by another line. The Rules row "the root reading ends at the group's `)`" is pinned only by `); test …` on one line.

Recommendation:
- Scan every byte of the line outside quotes, in order with the words: after the last word, and on lines with no words.
- Cases: the first two shapes above, the `bash -c` variant and the lone `)`, each reported from z-nile.
- Mutant: "parens counted only before a word".
- Record in E1 that the live case was re-run with F1 and F2 fixed, and then each alone.

### F3 [high] The root reading ends at any change of single-quote context, so a top-level cd ends at the first quoted word and a script's cd ends at the `'"'"'` idiom. "A top-level cd lasts to the end of the file" does not hold
Where: Design rule 3 ("a top-level cd lasts to the end of the file"); the zz-test sentence; `if rootDepth < 0 or q.ctx[abs] ~= rootCtx then rootDir = nil end`.
Evidence: the reset is permanent, and every single-quoted string has a context number of its own. Each of these is silent, though bash runs the test at the root, where `tests/run.luau` is missing:
- `cd "$ZN_ROOT"`, then `grep -q 'x' AGENTS.md`, then `test -f tests/run.luau`. AGENTS.md is also reported "from z-nile".
- `cd "$ZN_ROOT"`, then `check "AC1" bash -c 'test -f tests/run.luau'`. A child script inherits the directory it starts in.
- The same after `if [[ -n $ZN_ROOT ]]; then cd "$ZN_ROOT"; fi`.
- `check "AC1" bash -c 'cd "$ZN_ROOT" && grep -q '"'"'x'"'"' AGENTS.md && test -f tests/run.luau'`.
  - Round 1 F2's Consequences named this idiom (c0292 lines 30, 39, 57), and refute F2 answers "fixed". c0248 uses `'\''` in the same way.
  - Both idioms end a script's context and open a new one.
- The spec's only top-level case (`cd "$ZN_ROOT"` then `test -f tests/run.luau`) has no quote after the cd.

Recommendation:
- Keep the directory per context:
  - a single-quoted string opened where a root reading is on starts with that reading, because a script runs where its parent runs;
  - a cd inside a script ends with the script, as now;
  - a `'` that closes, followed by only `"'"` or `\'` and a reopening `'`, continues the same context.
- Cases: the four above, each reported from the root.
- Mutants: "a context change ends a top-level cd" and "the idiom ends the script".
- Fix the zz-test sentence, which should claim only what the code does.

### F4 [medium] Command position misses the command that `check` runs and the first word of a continued line after an operator. The grep rule now reads patterns main marks (a regression), and rule H misses the plainest helper call
Where: Design rule 6 (command position) and rule 4; Existing work ("every rule makes the scan report less except R").
Evidence:
- `check` in z-nile/lib/ac.sh runs `"$@"` as a command (`out=$("$@" 2>&1)`, where the check's functions are visible). Once the label is blanked, the next word is not taken as a command.
  - R0016's RC1 (done) is `check "RC1: …" grep -q -F "run: z-nile/setup.sh --tools" ../.github/workflows/board.yml`. c0371 reads `z-nile/setup.sh` from z-nile, a false report. c0141's module and main mark the pattern.
  - It is the only line in the finished-corpus diff that c0371 reads and c0141 does not, besides root readings. c0040 and R0025 use the same `check "…" grep` shape.
- `has() { grep -qF -- "$2" "$1"; }` then `check "AC1: x" has "$F" "src/nothing is gone"` reports `src/nothing`. That is quoted text passed to a search helper, which Solution bullet 3 covers. c0083's `check "AC1: …" suites \` followed by case names has this shape (it is restamped, so it is not scanned today).
- `x=$(foo \` then `  | grep -qF "src/nothing")` reports `src/nothing`.
  - The first word of a continued line is never in command position: `sep` is `not wasContinued` and the gap before the word is ignored.
  - c0141 marks it. R0002 (done) line 20 starts a continued line with `&& grep -qE …`.
- So the position rule reports more than c0141 in these shapes, and Existing work's claim is false.

Recommendation:
- Command position also includes:
  - the word after a `check` whose label was blanked;
  - the first word of a continued line whose gap holds `|`, `&&`, `||` or `;`.
- Cases, each reporting nothing:
  - R0016's RC1 line;
  - `check "AC1" has "$F" "src/nothing"` with `has` defined;
  - the continued `| grep`.
- One mutant each.
- Add both points to zz-test/shell-rules-key-on-command-position, whose list has the same gap.

### F5 [medium] Rule L counts grep's file operand as a match, ends the loop body at the first word `done` even inside a message, and ends an outer body at an inner loop's `done`. Each silences a path the loop opens, and the grep part has no case
Where: Design rule 7; `textOnlyLoop`.
Evidence: c0141's module reports each of these and c0371's is silent.
- `for f in tests/gone.md tests/run.luau; do if grep -qF "old rule" "$f"; then echo "$f still has the old rule"; exit 1; fi; done`:
  - The pattern `grep[^;|&\n]-["']%$f["']` matches any `"$f"` after a grep, its file argument included.
  - A negative grep of a missing file exits 2 and the check passes: AC11's own hazard.
- `for f in src/gone.luau; do grep -qF "$f" "$E" || { echo "c0001 is not done"; exit 1; }; test -f "$f"; done`: the body is cut at "done" inside the message.
- `for f in src/gone.luau; do for w in a b; do case "$w" in *"$f"*) ;; esac; done; test -f "$f"; done`: the body is cut at the inner `done`.
- Mutant MF (the grep sub-rule removed) leaves c0371's spec (without its live case) 8/8 and c0120's 4/4. The sub-rule has no case, and its one live consumer, c0193, uses `case`.

Recommendation:
- Count `"$NAME"` as matched only where it is grep's pattern: the first word that is not an option, or the word after `-e`. Use the same reader the word loop uses (zz-test/one-rule-one-function).
- Find the loop's own `done` by words outside quotes, counting nested `for`, `while` and `until` with `do`.
- Cases: the three above, reported. Also a loop shaped like c0083's `for fact in "…" "scripts/lib/suites.luau"; do grep -qF -- "$fact" "$s" || { echo "… $fact"; …; }; done`, still read as text.
- One mutant each.

### F6 [medium] Rule E's message covers command substitutions inside the message and a one-word echo that returns a path. The cost is not named
Where: Design rule 6; Existing work.
Evidence: c0141 reports both of these and c0371 does not.
- `x=1; echo "$(cat src/gone.luau)"`. The marked message runs to the closing quote, through the substitution's commands.
- `spec() { if [[ -f "$d/x.spec.luau" ]]; then echo "$d/x.spec.luau"; else echo tests/acceptance/c0077/gone.spec.luau; fi; }`, then `lune run tests/run -- "$(spec)"`.
  - c0099's finished spec locator is this shape (`else echo tests/acceptance/c0077/replace-file.spec.luau`).
  - f0147 (live) and R0034 return paths with the same idiom through variables.
  - c0121 line 30 puts a `$(…)` in a top-level echo message.
- Rule E is not in the capture ("found by the prototype"), so what it silences needs naming.

Recommendation:
- A message stops at `$(` or a backtick: the words inside a substitution are read as commands, with their own position.
- A message of one word is a value and is read. c0292's, d0297's and c0371's messages are several words, so they stay prose.
- Cases: both forms above reported, and the existing echo cases unchanged. One mutant each.

### F7 [medium] Several rules have no case that kills a plausible mutant
Where: Rules and mutants; E3.
Evidence: these mutants of the prototype survive both c0371's spec without its live case (8/8) and c0120's spec with the live scan (4/4):
- **MK.** A helper call is not ended by `;`, `&&`, `|` or a line end, only by leaving its script.
  - The case "a bare path argument is still read, and a command after the call" uses an unquoted path, which H never marks.
  - The behaviour itself is right: `has "$F" "x"; cat "src/gone.luau"` reports.
- **MBR.** `}` does not close a root group. Design rule 3 names `}`. `{ cd "$ZN_ROOT" && true; }; test -f z-nile/roots.luau` reports today, unpinned.
- **MS.** The Touched exemption of a root-read path takes the home form, `repoPath(home, …)` instead of `repoPath(from, …)`.
  - The behaviour is right today: `(cd "$ZN_ROOT" && test -f z-nile/new.luau)` is exempt under the entry `z-nile/new.luau`, and under `new.luau` in a home-form document.
  - No root case has a Touched entry, though zz-test line 78 tells a check to name work through `$ZN_ROOT`.
- **MB_\*.** Removing any one of `then`, `do`, `else`, `if`, `elif`, `while`, `until`, `!`, `}`, `time`, `xargs`, `env`, `command` or `exec` from `INTRODUCERS`. Only `{` is pinned.
  - The grep rule now depends on position, so under MB_if, `if grep -qF "src/x" f` becomes a false report.
- **MEO.** An echo's options are not skipped.
- **MSP.** A code span counts only inside double quotes. The Design says "inside a quoted argument"; the code marks a span anywhere.
- Related: an odd number of `` \` `` on a line marks the rest of the line as text, outside quotes too. `grep -qF "\`./zn" "$F" && test -f tests/gone.md` is silent, and c0141 reports it. No live line has an odd count.

Recommendation:
- One case and one Rules row per mutant above. For the introducers, one line per word, each followed by a path that must still be reported or a pattern that must not be.
- A span needs both ends inside the same quoted argument, with a case for the odd count.

Lesson: zz-test/seed-every-enumerated-case

### F8 [medium] The arrangement with c0141 leaves c0141's AC3 unspecified and its layer red, and rests on an unmerged PR
Where: Design, Arrangement with c0141; Regression guard (Overrides); Implementation step 1; Unknowns ("c0141 unfolded (PR #450)").
Evidence:
- **AC3 is not specified.** The document says AC3 "and its check line are replaced by a regression line that does not depend on the live tree (the spec file still loads …)", with no line given.
  - "The spec file still loads" passes while c0120's literal-reader, fixture or restamped case is red. A wrong move then passes c0141's layer, against c0141's own guard ("every case and assertion is kept").
  - The change is to be made after this review, so no review covers it.
- **c0141's layer is red.** E2 holds: with c0141's prototype and spec on today's main, c0120's live case is red on c0193's four words and on c0292.
  - c0141's layer edits c0120's spec, so its `--affected` gate runs that case red whatever AC3 says.
  - zz-execute says to finish a layer "when they are green", and its stop conditions include "Main is red". Nothing tells the executor that this red is expected until c0371's layer.
- **PR #450 is not merged.** #450 ("R0062 keeps c0139 alone (unfold c0141)") is open. origin/main still has `raft: R0062` in c0141.md and `issues: [c0139, c0141]` in R0062, yet c0371.md states c0141 as unfolded.
  - If R0062 is readied first, c0141 runs alone, with an AC3 that is red at its finish.
- **The module is missing from Overrides.** c0141's Design says the module "stays under 'never edit promoted specs' … a later item can change it only through an `Overrides:` line". c0371 is that later item, and its Overrides line names only the spec. Round 1 F6 asked for this; refute F6 does not answer it.

Recommendation:
- Write c0141's replacement AC3 in c0371.md now, word for word with its check line. For example: "AC3: c0120's check-paths spec still passes its literal-reader, fixture and restamped cases; its live scan is c0371's AC2".
  - The check runs the spec and requires those three case names to show no `FAIL <spec> :: <case>` line, and only the live case's name to be allowed to fail (c0083's `cases_in` shape).
- Say in Implementation step 1, and for z-raft's Order, that c0141's layer finishes with c0120's live case red on exactly c0292's and c0193's lines, named in its PR. This is the user's arrangement, not a red main to escalate.
- Make #450 merged a precondition of rafting c0371.
- Add `z-nile/tests/acceptance/c0120/checkpaths.luau` to the Overrides line.
- If the user's "absorbs" meant one item (c0141's two specs and Design carried into c0371, c0141 closed), that avoids the red layer and the AC3 rewrite. Ask, since the ruling text ("unfold c0141 from R0062 into c0371") reads either way.

Lesson: z-design/design-the-execution-window

### F9 [low] Some answers and statements are not true
Where: design-refute-001 F6, F10 and F13; Affected specs; E3; E6; AC4.
Evidence:
- **F6.** "c0120's spec requires the module, so the selector picks it": in a clone with the module, `lune run z-nile/affected -- z-nile/tests/acceptance/c0120/checkpaths.luau` prints nothing. A promoted spec is selected by its watch.txt, and c0120's does not list the module.
  - `./zn finish` will write the module into c0141's and c0371's own watch.txt, so a later module change runs c0371's live case.
  - It never runs c0120's literal-reader or fixture cases; those run only at `--full`.
- **F10.** The Affected specs command prints 31 specs, not one: c0120's spec plus the 30 whose watch lists `tests/inputs.tsv`.
  - I ran those 30 with the new line, before promotion: 257 passed, 0 failed.
  - Three are slow: c0117 control-cli 214 s, dispatch-cli 160 s and dispatch-guards 121 s. c0371's layer gate therefore takes minutes longer; say so.
- **F13 and E6.** Refute F13 says "the header comment of the spec names echo and printf", and E6 says "the spec header says so". c0371's spec header names neither echo nor printf, H, L or E6's `case )` limit, and still says "until its subshell closes".
  - The change to c0120's header comment (Design item 8) is neither in the prototype nor specified.
- **E3** counts 19 mutants; the table names 20 ids, with no M12.
- **AC4** greps only the spec's path in `tests/inputs.tsv`, so a comment naming it passes. Grep the whole line, `tests/acceptance/c0371/check-paths-homes.spec.luau<TAB>*`.
- The experiments do not say they ran under `./zn run --time`.

Recommendation: correct each statement and AC4's grep. For the module, either accept that `--full` is the only run of c0120's other cases (and say so), or name another route.

Lesson: z-design/restated-rules-move-together (a "fixed" answer that names a sentence checks that the sentence is gone).

## Lesson candidates (for the lead)
- zz-test: a quote-aware pass over shell text skips comments (a `#` that begins a word, outside quotes, at the top level). Why: c0371's pass read the template's "its project's" and inverted every context after it in 198 of 240 check.sh files. Check: what state does the pass hold after `# the item's check`?
- zz-test: a reader that tracks structure characters (parens, braces) scans the whole line, not only the gaps before words. Why: a `)` that ended a line was never counted. Check: what does the reader do with a `)` that ends its line?
- z-design: when a live-tree case stays green after a rule change, re-run it with each fix alone. Why: c0292 passed only because two defects cancelled, and fixing one turned it red. Check: does the live case still pass with each defect fixed on its own?
- zz-test/shell-rules-key-on-command-position should add a wrapper that runs its arguments as a command (ac.sh's `check`) and the operator that starts a continued line (F4).

Verdict: changes
